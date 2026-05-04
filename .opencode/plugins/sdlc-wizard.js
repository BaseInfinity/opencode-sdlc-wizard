// OpenCode SDLC Wizard plugin shim.
//
// Translates OpenCode plugin events to the portable bash hooks at
// .opencode/hooks/*.sh (identical content across the parent claude-sdlc-wizard
// and codex-sdlc-wizard siblings — only the registration surface differs).
//
// Why a JS shim, not native bash hooks: OpenCode's hook system is plugin-based
// (JS/TS modules at .opencode/plugins/*.js), not declarative like Claude
// Code's .claude/settings.json hooks or Codex's .codex/hooks.json. The plugin
// is glue; the bash logic is the value.
//
// Event-handler API (per https://opencode.ai/docs/plugins/):
//   - generic `event` handler receives `{ event }` and branches on `event.type`
//     for session-lifecycle dispatch (session.created, session.idle, etc.)
//   - tool execution dispatch is named: `"tool.execute.before"` receives
//     `(input, output)`, where `input.tool` is the lowercase tool id
//     (`write`, `edit`, `apply_patch`) and `output.args` carries the
//     tool-specific arguments
//   - `"experimental.session.compacting"` receives `(input, output)` too;
//     throwing from the handler propagates as a block (verified by Codex
//     review against OpenCode source 2026-05-03)
//
// Session-start race (verified live against OpenCode 1.14.33, 2026-05-04):
//   OpenCode publishes `session.created` ~1–2ms after plugin loading begins,
//   which is BEFORE the async plugin factory resolves and the returned
//   handlers are subscribed to the bus. Plugins consistently miss the very
//   first `session.created` and only start receiving subsequent session.*
//   events. To ship reliable session-start nudges anyway, this plugin runs
//   the session-start hooks on the FIRST `session.*` event it observes and
//   then dedupes — that fires in the window we actually have access to,
//   independent of OpenCode's race. (If OpenCode later fixes the race, this
//   still works — the dedupe means we don't double-run.)
//
// Exit-code contract from the bash hooks:
//   exit 0 → advisory success; stdout printed to stderr as informational
//   exit 2 → block (only honored on tool.execute.before and
//            experimental.session.compacting per Claude convention; we
//            re-throw to propagate in OpenCode)
//
// Hook invocation transport (verified live against OpenCode 1.14.33,
// 2026-05-04): `node:child_process.execFile` does not resolve in OpenCode's
// bundled Bun runtime — its callback is never invoked, hanging the plugin's
// async handler. The plugin context provides Bun's `$` shell API; we use
// that to run hooks. `node:child_process` import stays for the type/parse
// path but is unused at runtime; if a future OpenCode build runs plugins
// under plain Node, the same `$` argument is conventionally provided by
// Bun's compatibility shim. There is no plain-Node fallback because
// OpenCode is Bun-only as of this version.

import path from "node:path";
import fs from "node:fs";

// Tool ids we care about for TDD-pretool. OpenCode uses lowercase.
const TDD_TARGET_TOOLS = new Set(["write", "edit", "apply_patch", "multiedit"]);

// Source file extensions worth nudging on TDD (skip docs, configs, scripts).
const SOURCE_GLOB_RE = /\.(js|jsx|ts|tsx|mjs|cjs|py|go|rs|rb|java|kt|swift|c|h|cpp|hpp|cs)$/i;

// Path patterns that mean "this IS a test/spec file, don't nag the user about
// writing a test before they edit it".
const TEST_PATH_RE = /\b(test|tests|spec|specs|__tests__|fixtures?|e2e|integration)\b/i;

function resolveHookPath(directory, hookName) {
  const candidates = [
    path.join(directory, ".opencode", "hooks", hookName),
    path.join(directory, "hooks", hookName), // dev-mode (this repo's own layout)
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function runHook(hookPath) {
  // Synchronous shell-out. We use spawnSync rather than the async $ API or
  // node:child_process.execFile because both async paths hang inside
  // OpenCode's bundled Bun runtime in 1.14.33 — verified live 2026-05-04.
  // SpawnSync blocks the event loop briefly (one bash hook ≈ 50–500ms) but
  // completes deterministically, which is preferable to a hook that never
  // resolves and silently swallows the SDLC nudge.
  if (!hookPath) {
    return { stdout: "", stderr: "", code: 0, missing: true };
  }
  try {
    if (typeof Bun !== "undefined" && typeof Bun.spawnSync === "function") {
      const r = Bun.spawnSync(["bash", hookPath]);
      return {
        stdout: (r.stdout && r.stdout.toString()) || "",
        stderr: (r.stderr && r.stderr.toString()) || "",
        code: typeof r.exitCode === "number" ? r.exitCode : 0,
        missing: false,
      };
    }
    // Plain-Node fallback (theoretical — OpenCode is Bun-only as of 1.14.33).
    const cp = require("node:child_process");
    const stdout = cp.execFileSync("bash", [hookPath], { timeout: 10000 });
    return { stdout: stdout.toString(), stderr: "", code: 0, missing: false };
  } catch (e) {
    return {
      stdout: "",
      stderr: e && e.message ? e.message : String(e),
      code: typeof e?.status === "number" ? e.status : 1,
      missing: false,
    };
  }
}

// Extract a file path from arbitrary tool args. Different OpenCode tools name
// the path differently:
//   write/edit:   args.filePath  (per docs example)
//   apply_patch:  args.input is a unified-diff blob, no single path field —
//                 we fall back to the first `*** Update File:` or
//                 `*** Add File:` line if present.
function extractFilePath(toolName, args) {
  if (!args || typeof args !== "object") return "";
  if (typeof args.filePath === "string") return args.filePath;
  if (typeof args.file_path === "string") return args.file_path; // legacy
  if (typeof args.path === "string") return args.path;           // belt-and-suspenders
  if (toolName === "apply_patch" && typeof args.input === "string") {
    const m = args.input.match(/^\*\*\* (?:Update|Add) File:\s+(.+)$/m);
    if (m) return m[1].trim();
  }
  return "";
}

function shouldNudgeTdd(toolName, filePath) {
  if (!TDD_TARGET_TOOLS.has(toolName)) return false;
  if (!filePath) return true; // unknown path → nudge by default
  if (TEST_PATH_RE.test(filePath)) return false; // editing a test → already TDD
  if (!SOURCE_GLOB_RE.test(filePath)) return false; // not a source file → skip
  return true;
}

export const SdlcWizardPlugin = async ({ directory }) => {
  // Per-plugin-instance dedupe flag for session-start hooks. Survives across
  // multiple event invocations within the same OpenCode process. Reset is
  // unnecessary — a fresh OpenCode invocation gets a fresh module instance.
  let sessionStartFired = false;

  async function runSessionStartHooks() {
    const messages = [];
    for (const hookName of [
      "instructions-loaded-check.sh",
      "model-effort-check.sh",
    ]) {
      const hookPath = resolveHookPath(directory, hookName);
      const r = runHook(hookPath);
      if (r.stdout) messages.push(r.stdout.trim());
    }
    if (messages.length > 0) {
      process.stderr.write(
        "\n=== SDLC Wizard ===\n" + messages.join("\n\n") + "\n===================\n\n",
      );
    }
  }

  return {
    // Generic event handler — branches on event.type for session-lifecycle
    // dispatch since OpenCode's session events flow through this channel,
    // not through named keys.
    //
    // Session-start hooks fire on the FIRST `session.*` event we observe in
    // this OpenCode process, not strictly on `session.created`, because
    // OpenCode publishes session.created before plugin factories resolve and
    // subscribe (race condition). The dedupe flag means we run the hooks
    // exactly once per process lifetime regardless of which session event
    // arrives first (session.updated, session.idle, session.created, etc.).
    event: async ({ event }) => {
      if (!event) return;
      if (
        !sessionStartFired &&
        typeof event.type === "string" &&
        event.type.startsWith("session.")
      ) {
        sessionStartFired = true;
        await runSessionStartHooks();
      }
    },

    // Pre-tool nudge for TDD on source-file edits. OpenCode tool ids are
    // lowercase (write / edit / apply_patch / multiedit). Args live at
    // output.args per docs.
    "tool.execute.before": async (input, output) => {
      const toolName = input && typeof input.tool === "string" ? input.tool : "";
      const args = output && output.args ? output.args : {};
      const filePath = extractFilePath(toolName, args);
      if (!shouldNudgeTdd(toolName, filePath)) return;
      const hookPath = resolveHookPath(directory, "tdd-pretool-check.sh");
      const r = runHook(hookPath);
      if (r.stdout) process.stderr.write(r.stdout);
    },

    // Pre-compact gate. Throwing from this handler propagates as a block
    // (verified against OpenCode source 2026-05-03 — the dispatcher awaits
    // without catch, so throws bubble to the caller).
    "experimental.session.compacting": async () => {
      const hookPath = resolveHookPath(directory, "precompact-seam-check.sh");
      const r = runHook(hookPath);
      if (r.stdout) process.stderr.write(r.stdout);
      if (r.code === 2) {
        const err = new Error(
          "SDLC Wizard: compact blocked by precompact-seam-check (PENDING_RECHECK or in-flight rebase/merge).",
        );
        err.blocked = true;
        throw err;
      }
    },
  };
};

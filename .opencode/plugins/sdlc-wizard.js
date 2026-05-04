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
// Exit-code contract from the bash hooks:
//   exit 0 → advisory success; stdout printed to stderr as informational
//   exit 2 → block (only honored on tool.execute.before and
//            experimental.session.compacting per Claude convention; we
//            re-throw to propagate in OpenCode)

import { execFile } from "node:child_process";
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

function runHook(hookPath, env = {}) {
  if (!hookPath) {
    return Promise.resolve({ stdout: "", stderr: "", code: 0, missing: true });
  }
  return new Promise((resolve) => {
    execFile(
      "bash",
      [hookPath],
      { env: { ...process.env, ...env }, timeout: 10000 },
      (err, stdout, stderr) => {
        const code = err && typeof err.code === "number" ? err.code : 0;
        resolve({ stdout: stdout || "", stderr: stderr || "", code, missing: false });
      },
    );
  });
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
  return {
    // Generic event handler — branches on event.type for session-lifecycle
    // dispatch since OpenCode's session events flow through this channel,
    // not through named keys.
    event: async ({ event }) => {
      if (!event || event.type !== "session.created") return;
      const messages = [];
      for (const hookName of [
        "instructions-loaded-check.sh",
        "model-effort-check.sh",
      ]) {
        const hookPath = resolveHookPath(directory, hookName);
        const r = await runHook(hookPath);
        if (r.stdout) messages.push(r.stdout.trim());
      }
      if (messages.length > 0) {
        process.stderr.write(
          "\n=== SDLC Wizard ===\n" + messages.join("\n\n") + "\n===================\n\n",
        );
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
      const r = await runHook(hookPath);
      if (r.stdout) process.stderr.write(r.stdout);
    },

    // Pre-compact gate. Throwing from this handler propagates as a block
    // (verified against OpenCode source 2026-05-03 — the dispatcher awaits
    // without catch, so throws bubble to the caller).
    "experimental.session.compacting": async () => {
      const hookPath = resolveHookPath(directory, "precompact-seam-check.sh");
      const r = await runHook(hookPath);
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

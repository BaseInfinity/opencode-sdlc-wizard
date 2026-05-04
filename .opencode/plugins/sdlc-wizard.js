// OpenCode SDLC Wizard plugin shim.
//
// OpenCode does not have Claude Code's hook config schema. Instead it has a
// plugin system at .opencode/plugins/*.js that subscribes to events. This
// shim translates OpenCode events to invocations of the portable bash hooks
// that live at hooks/<name>.sh (identical to the parent claude-sdlc-wizard
// and codex-sdlc-wizard siblings).
//
// Why a shim instead of native JS hooks: the bash scripts are the value.
// They're battle-tested across two siblings. Re-implementing them in JS would
// re-introduce bugs that have already been found and fixed upstream. The shim
// is ~50 lines of glue; the bash logic is hundreds of lines of accumulated
// SDLC enforcement.
//
// Event mapping (Claude Code → OpenCode):
//   UserPromptSubmit  → no direct event. SDLC BASELINE moves to AGENTS.md.
//   SessionStart      → session.created
//   PreToolUse        → tool.execute.before
//   PreCompact        → experimental.session.compacting
//
// Exit-code contract:
//   exit 0 → success, stdout printed as advisory message
//   exit 2 → block the action (only honored on tool.execute.before
//            and experimental.session.compacting per Claude convention)

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
import fs from "node:fs";

const execFileP = promisify(execFile);

// Resolve hooks directory. The plugin lives at .opencode/plugins/sdlc-wizard.js
// in the install target; hooks live at .opencode/hooks/ alongside.
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

async function runHook(hookPath, env = {}, stdinPayload = null) {
  if (!hookPath) return { stdout: "", stderr: "", code: 0, missing: true };
  return new Promise((resolve) => {
    const child = execFile(
      "bash",
      [hookPath],
      { env: { ...process.env, ...env }, timeout: 10000 },
      (err, stdout, stderr) => {
        const code = err && typeof err.code === "number" ? err.code : 0;
        resolve({ stdout: stdout || "", stderr: stderr || "", code, missing: false });
      },
    );
    if (stdinPayload != null && child.stdin) {
      child.stdin.write(stdinPayload);
      child.stdin.end();
    }
  });
}

export const SdlcWizardPlugin = async ({ directory, $, client }) => {
  const _ = $; // reserved for future Bun-shell use
  const _client = client;
  const TDD_TARGET_TOOLS = new Set(["Write", "Edit", "MultiEdit"]);
  const SOURCE_GLOB_RE = /\.(js|jsx|ts|tsx|mjs|cjs|py|go|rs|rb|java|kt|swift|c|h|cpp|hpp|cs)$/i;

  return {
    "session.created": async () => {
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
        process.stderr.write("\n=== SDLC Wizard ===\n" + messages.join("\n\n") + "\n===================\n\n");
      }
    },

    "tool.execute.before": async ({ tool, args }) => {
      if (!tool || !TDD_TARGET_TOOLS.has(tool)) return;
      const filePath = args && (args.file_path || args.path) ? (args.file_path || args.path) : "";
      if (filePath && !SOURCE_GLOB_RE.test(filePath)) return;
      if (filePath && /\b(test|spec|__tests__|fixtures?)\b/i.test(filePath)) return;
      const hookPath = resolveHookPath(directory, "tdd-pretool-check.sh");
      const r = await runHook(hookPath);
      if (r.stdout) process.stderr.write(r.stdout);
    },

    "experimental.session.compacting": async () => {
      const hookPath = resolveHookPath(directory, "precompact-seam-check.sh");
      const r = await runHook(hookPath);
      if (r.stdout) process.stderr.write(r.stdout);
      if (r.code === 2) {
        const err = new Error("SDLC Wizard: compact blocked by precompact-seam-check (PENDING_RECHECK or in-flight rebase/merge).");
        err.blocked = true;
        throw err;
      }
    },
  };
};

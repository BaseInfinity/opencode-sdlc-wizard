# Changelog

All notable changes to opencode-sdlc-wizard.

## [0.1.0] - 2026-05-03

### Added — Phase A port complete

The OpenCode sibling now ships a working SDLC enforcement layer. Phase A
scope (per `BaseInfinity/claude-sdlc-wizard` ROADMAP #9) is closed.

**Bundled artifacts:**

- `AGENTS.md` — primary instruction file, loaded automatically at session
  start. Contains SDLC Baseline (replacing the per-prompt nudge from the
  Claude/Codex siblings since OpenCode has no `UserPromptSubmit` analog).
- `.opencode/plugins/sdlc-wizard.js` — JS plugin shim. Subscribes to
  OpenCode events (`session.created`, `tool.execute.before`,
  `experimental.session.compacting`) and shells out to the portable bash
  hooks. Honors exit-code-2 block contract on the compact event.
- `.opencode/hooks/*.sh` — 5 bash hooks ported verbatim from the parent:
  `sdlc-prompt-check.sh`, `tdd-pretool-check.sh`,
  `instructions-loaded-check.sh`, `model-effort-check.sh`,
  `precompact-seam-check.sh` (plus the shared helper
  `_find-sdlc-root.sh`). The bash logic is the value — battle-tested
  across two earlier siblings; the JS plugin is just glue.
- `skills/{sdlc,setup,update,feedback}/SKILL.md` — 4 skills installed at
  `.opencode/skills/` in target repos. Format is identical to Claude
  Code's per ROADMAP #91; OpenCode's docs explicitly support
  Claude-compatible skill paths.
- `install.sh` — non-destructive merge installer. Mirrors codex-sdlc-wizard
  pattern. Idempotent (re-run is safe), per-file MATCH/CUSTOMIZED/MISSING
  classification, `--force` opt-in for overwrite, writes a
  `.opencode/.wizard-stamp` metadata marker for future drift detection.

### Tests

- `tests/test-bundle-integrity.sh` — 48 tests covering hook
  presence + executability, hook dual-location no-drift, plugin
  exports, OpenCode event-name correctness (no Claude event leaks).
- `tests/test-plugin-shim.sh` — 8 tests covering plugin ESM
  parseability, bash hook syntax, source-glob regex classification,
  exit-2 block contract.
- `tests/test-install.sh` — 11 tests covering fresh install,
  idempotent re-install, customization preservation, `--force`
  overwrite, skills install location, untouched user `opencode.json`,
  help/error flags.

**Total: 67 tests, all green.**

### OpenCode Adaptation Notes

- **No `UserPromptSubmit` equivalent.** The per-prompt SDLC BASELINE nudge
  from Claude/Codex moves to AGENTS.md (loaded once per session). Tradeoff:
  loses per-prompt repetition, but content survives the entire session
  without per-message token cost.
- **Hook config is plugin-based.** OpenCode does not have a
  declarative `hooks.json` schema like Claude Code or Codex. Instead, JS
  plugins at `.opencode/plugins/*.js` subscribe to events. This wizard's
  plugin shim is the OpenCode-specific adapter; the bash hooks themselves
  are unchanged across all three siblings.
- **Skills install at `.opencode/skills/`.** OpenCode also reads
  `.claude/skills/` for cross-tool compatibility, but installing into the
  OpenCode-native location keeps things explicit.
- **`opencode.json` is left alone.** v0.1.0 deliberately does not touch
  user `opencode.json` — backend selection (model pin) is a Phase B concern.

### Phase B / Phase C — deferred

- **Phase B** — backend matrix proof (Ollama + Qwen-Coder, Azure OpenAI,
  Together/Groq, Anthropic baseline). Ship score-history + capability-floor
  documentation when paired runs complete.
- **Phase C** — hardware scout for the local-tier compute requirement.
  Existing gaming/Windows laptops first; $200-400 rig or cloud GPU
  rental only if insufficient.

These phases ship as separate releases. v0.1.0 is the foundation port.

## [0.0.1] - 2026-05-03

### Bootstrap stage

Repo created, `HANDOFF.md` written for the implementation session.
No installable artifacts. See `HANDOFF.md` for the bootstrap-session
brain dump.

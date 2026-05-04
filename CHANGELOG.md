# Changelog

All notable changes to opencode-sdlc-wizard.

## [0.2.0] - 2026-05-04

### Fixed — live OpenCode E2E reliability (validation against 1.14.33)

Static checks (parse, regex, signature) passed in v0.1.0 but **the wizard's
session-start nudges silently swallowed under a real OpenCode process**.
Caught by E2E validation against `opencode-ai@1.14.33` 2026-05-04 and fixed
in v0.2.0. Each fix has a regression test in `tests/test-plugin-shim.sh`.

- **Session-start race.** OpenCode publishes `session.created` ~1–2 ms after
  plugin loading begins, **before** async plugin factories resolve and
  subscribe to the event bus. The strict `event.type === "session.created"`
  discriminator from v0.1.0's round-1 fix never fired in live runs.
  v0.2.0 uses the FIRST `session.*` event the handler observes (with a
  closure dedupe), which arrives in the window the plugin actually has
  access to. Survives both the race and a future OpenCode fix that closes it.
- **Async hook execution hung.** Both `node:child_process.execFile` and
  Bun's `$` shell API hang inside OpenCode's bundled Bun runtime — the
  callback / promise never resolves, swallowing all hook output. v0.2.0
  switches `runHook` to `Bun.spawnSync` (synchronous; can't hang the event
  loop). Single bash hook ≈ 50–500 ms — acceptable cost for deterministic
  completion.

After both fixes, the SDLC Wizard banner reaches OpenCode stderr live (the
`=== SDLC Wizard ===` block renders the same way it does in Claude / Codex).

### Added — privacy-first backend picker

The differentiator that justifies this sibling's existence. Other wizards in
the family (`agentic-sdlc-wizard`, `codex-sdlc-wizard`) are vendor-bound to
Claude or Codex. OpenCode's edge is multi-backend portability — and v0.2.0
makes that edge usable instead of a "you can pin a model in opencode.json"
README footnote.

**New artifacts:**

- `scripts/detect-backends.sh` — probes PATH + env vars for available
  backends across the four privacy tiers and outputs JSON with a
  `recommendation` field (privacy-first cascade — prefers `private_local`
  whenever a local LLM runtime is on PATH).
- `scripts/configure-backend.sh` — writes/merges `opencode.json` for a
  chosen `--tier --provider --model` combination. Idempotent (re-running
  with same args produces byte-identical output), preserves unrelated keys,
  refuses to clobber an existing `model` pin without `--force`. Supports
  `--print-only` for skill-driven dry runs.
- `PRIVACY.md` — tier model + Ollama walkthrough + private-path
  verification checklist.

**Updated:**

- `install.sh` installs the two scripts at `.opencode/scripts/` and chmod
  +x's them. Adds a privacy-tier hint to its post-install Next Steps.
- `setup-wizard` skill now invokes the detector + configurator with concrete
  privacy-first defaults instead of the prior placeholder backend question.
- `AGENTS.md` + `README.md` lead with the privacy-tier picker and link
  `PRIVACY.md`.

### Tests

- `tests/test-backend-picker.sh` — 21 tests covering detector JSON shape,
  env-var detection, recommendation cascade, configurator output for
  ollama/anthropic/azure tiers, custom-provider `models` entries (so
  OpenCode can resolve the pin), canonical provider IDs (`amazon-bedrock`
  / `togetherai`), deep-merge of existing provider blocks, idempotency
  via byte-identical re-runs, no-clobber guard, `--force` override,
  `--print-only` dry-run.
- Bundle integrity: scripts presence + bash syntax + tier-name guards;
  PRIVACY.md tier coverage. `tests/test-bundle-integrity.sh` 57 → 68.
- Install behavior: scripts installed at `.opencode/scripts/` + executable.
  `tests/test-install.sh` 12 → 13.

**Total: 113 tests, all green** (68 + 11 + 13 + 21 across 4 suites).

### Tiers supported

| Tier | Detector aliases → canonical provider ID written to opencode.json |
|------|--------------------------------------------------------------------|
| `private_local` | ollama / lm_studio→`lmstudio` / llama_cpp→`llamacpp` / vllm |
| `enterprise` | azure_openai→`azure` / aws_bedrock→`amazon-bedrock` |
| `hosted_oss` | together→`togetherai` / groq / openrouter |
| `proprietary` | anthropic / openai |

Local providers use OpenCode's `@ai-sdk/openai-compatible` provider with
each runtime's default localhost port and a `models` entry so OpenCode can
resolve the pin (custom providers without `models` raise
`ProviderModelNotFoundError`). API keys are referenced via `{env:VAR}`
substitution — no secrets land in `opencode.json`.

Detector emits user-friendly aliases (`aws_bedrock`, `together`,
`lm_studio`); the configurator accepts the alias and writes the canonical
OpenCode/models.dev provider ID. Built-in providers (`anthropic`, `openai`,
`azure`, `amazon-bedrock`) skip the `models` block — their model registry
comes from models.dev.

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

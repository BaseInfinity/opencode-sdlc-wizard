# Changelog

All notable changes to opencode-sdlc-wizard.

## [0.5.0] - 2026-05-05

### Added — `npx opencode-sdlc-wizard check` subcommand

Symmetric companion to `init`. Answers "is this install behind upstream?"
with an exit code that skills, hooks, and CI can consume:

- `0` — current
- `1` — behind (also prints installed + latest versions)
- `2` — not installed (no `.opencode/.wizard-stamp`) or fetch failed

```bash
npx opencode-sdlc-wizard check                  # human-readable
npx opencode-sdlc-wizard check --json           # {installed, latest, status, target_dir}
npx opencode-sdlc-wizard check --target-dir /p
```

Backed by `scripts/check-updates.sh` (also installed at
`.opencode/scripts/check-updates.sh` so the `update-wizard` skill
and `instructions-loaded-check.sh` hook can invoke it directly).

### Fixed — hook references parent npm package

`.opencode/hooks/instructions-loaded-check.sh` ran
`npm view agentic-sdlc-wizard version` (parent's npm name) when
checking for staleness. End users of `opencode-sdlc-wizard` would see
"upgrade-available" nudges pointing at the wrong wizard. Switched
to `npm view opencode-sdlc-wizard version`. Mirror at `hooks/` synced.

`.opencode/hooks/sdlc-prompt-check.sh` referenced
`CLAUDE_CODE_SDLC_WIZARD.md` in a comment; clarified that the hook is
Claude-Code-flavored and the OpenCode runtime has no
`UserPromptSubmit` analog so the fire-log is informational.

### Added — extended bundle-drift coverage (hooks)

`tests/test-bundle-drift.sh` extended with new classes:
- T9: hooks must NOT have executable references to parent-wizard
  npm packages (`npm view agentic-sdlc-wizard`,
  `npm install claude-sdlc-wizard`, etc.). Comments referencing the
  parent are OK (informational).
- T10: hook dual-location no-drift (every `.opencode/hooks/<f>` must
  byte-match `hooks/<f>`).

Test count grew from 28 → 47 in `test-bundle-drift.sh`.

### Tests

- `tests/test-check-cli.sh` — 10 tests: script existence + bash syntax,
  --help mentions stamp/installed/upstream, missing stamp → rc=2,
  current → rc=0, behind → rc=1, --json shape, CLI passthrough,
  --json passthrough, --help mentions both init and check.
- `tests/test-bundle-drift.sh` extended with hook checks (28 → 47).

**Total: 221 tests across 9 suites** (73 bundle + 11 plugin +
13 install + 21 picker + 10 CLI + 10 cross-model-review +
26 domain-templates + 47 bundle-drift + 10 check-cli).

## [0.4.1] - 2026-05-05

### Fixed — bundle-drift test caught + fixed real reference bug

`skills/sdlc/SKILL.md` (kept verbatim from parent in v0.1.0) referenced
`scripts/codex-review-with-progress.sh` — a parent-only helper we
never ported. New consumers running `skill({ name: "sdlc" })` would
hit a missing-script dead end.

### Added — `tests/test-bundle-drift.sh` (28 tests)

Catches future internal-reference drift before it ships:
- Every `scripts/<name>.sh` reference in skills/AGENTS.md/README/PRIVACY
  must resolve to a real file
- Every `skill({ name: "<id>" })` reference must resolve to a shipping
  skill
- Every script in `scripts/` must be listed in install.sh
- Every skill dir in `skills/` must be listed in install.sh
- install.sh's REQUIRED_SOURCES + declare_target arrays must stay in
  sync (orphaned source = silent install at wrong path)
- Skill dir name == frontmatter name (redundant guard, defense in
  depth)

Total: 192 tests, all green (73 + 11 + 13 + 21 + 10 + 10 + 26 + 28).

### Improved — `skills/sdlc/SKILL.md` cross-model-review pointer

The cross-model review section now points to
`skill({ name: "cross-model-review" })` as the OSS-tier alternative to
the codex flow. Previously the skill assumed codex; v0.3.1 shipped the
alternative skill, v0.4.1 surfaces it from the canonical SDLC workflow.

Also documents the `</dev/null` codex-stdin gotcha discovered live in
v0.2.0 + v0.3.0 ship work.

## [0.4.0] - 2026-05-04

### Added — domain-adaptive TESTING.md templates

The setup-wizard skill no longer assumes web/API. v0.4.0 ships four
domain-specific TESTING.md templates that the skill picks based on
repo signals:

- **firmware**: HIL / SIL / config-validate / unit pyramid; device
  matrix doc; mocking rules forbid mocked HIL
- **data-science**: model-eval / pipeline-integration / data-validation
  / unit pyramid; notebook reproducibility; train/serve skew check
- **cli**: integration-heavy diamond (process spawn + behavior contract
  + unit); argv-flag matrix; snapshot tests; OS-contract mocking rules
- **web** (default): integration-heavy diamond (E2E / integration /
  unit); API contract tests for every endpoint; real-DB mocking rules

Templates live at `templates/testing/<domain>.md` in the repo and
install at `.opencode/templates/<domain>.md` in target repos. The
`setup-wizard` skill detects the domain from concrete signals
(Makefile flash targets / `.ipynb` / `bin` package field / fallback)
and copies the matching template, substituting `<...>` placeholders
with the project's detected commands.

### Tests

- `tests/test-domain-templates.sh` — 26 tests: 4 templates exist, each
  has appropriate domain markers (HIL / notebook / argv / E2E), each
  describes a layered structure, install ships each to
  `.opencode/templates/testing/`, setup-wizard skill mentions all 4
  domains and references the templates directory, package.json
  files[] includes `templates/`.
- `tests/test-bundle-integrity.sh` — already covers skill + script
  set; templates count via the new test suite.

**Total: 164 tests, all green** (73 bundle + 11 plugin + 13 install +
21 picker + 10 CLI + 10 cross-model-review + 26 domain-templates).

## [0.3.1] - 2026-05-04

### Added — `cross-model-review` skill (OSS-tier reviewer)

Removes the OpenAI lock from the SDLC review loop. v0.2.0 made the
**coder** any-backend; v0.3.1 makes the **reviewer** any-backend too.
Now the entire SDLC plan→TDD→self-review→cross-model-review loop can
run with zero Anthropic+OpenAI dependency.

**Bundled artifacts:**

- `skills/cross-model-review/SKILL.md` — adaptive skill that picks an
  OSS-tier reviewer model and runs a cross-model review through
  OpenCode. Default suggestion: `togetherai/deepseek-ai/DeepSeek-V3`
  for deep reasoning at ~$0.27/M input (pennies per review). Local
  Ollama path documented for air-gapped contexts.
- `scripts/cross-model-review.sh` — non-interactive wrapper. Reads
  `.reviews/handoff.json` + `.reviews/response.json`, composes the
  recheck prompt, invokes `opencode run --model <provider>/<model>`,
  writes verdict to `.reviews/latest-review.md`. Symmetric to the
  codex flow.
- Provider-alias resolution shared with `configure-backend.sh`
  (`together` → `togetherai`, `aws_bedrock` → `amazon-bedrock`, etc.)

**Recommended reviewers:**

| Tier | Provider | Model | Why |
|------|----------|-------|-----|
| `private_local` | ollama | `qwen2.5-coder:32b` | Code-tuned, zero egress |
| `hosted_oss` | togetherai | `deepseek-ai/DeepSeek-V3` | Strongest reasoning OSS |
| `hosted_oss` | groq | `llama-3.3-70b-versatile` | Fastest hosted, free tier |

The two reviewer flows (codex + cross-model-review) produce
structurally identical `.reviews/latest-review.md` artifacts —
downstream consumers don't care which reviewer ran.

### Tests

- `tests/test-cross-model-review.sh` — 10 tests via stubbed `opencode`
  on PATH: script exists/parses, `--help` prints usage, rejects
  invocation without required flags, invokes opencode with correct
  `--model <provider>/<model>` arg, writes default + `--output-path`
  override, refuses without `.reviews/handoff.json`, alias resolution
  (`together` → `togetherai` in arg), `--print-prompt` previews
  without invoking opencode.
- `tests/test-bundle-integrity.sh` extended: skill set is now 5
  (added `cross-model-review`), scripts loop covers all 3.

**Total: 138 tests, all green** (73 bundle + 11 plugin + 13 install +
21 picker + 10 CLI + 10 cross-model-review).

## [0.3.0] - 2026-05-04

### Added — `npx opencode-sdlc-wizard init` CLI

Closes the install ergonomics gap. Previously the only paths were
`git clone + bash install.sh` or `npm i + bash node_modules/.../install.sh`;
neither reads as "easy as hell." v0.3.0 ships a `bin` entry plus a thin
Node wrapper at `cli/bin/opencode-sdlc-wizard.js` that shells out to
`install.sh`.

```bash
npx opencode-sdlc-wizard init
npx opencode-sdlc-wizard init --target-dir /path
npx opencode-sdlc-wizard init --dry-run
npx opencode-sdlc-wizard --version
npx opencode-sdlc-wizard --help
```

Wrapper-level `--dry-run` previews the bundle install without touching
the target. All other flags (`--target-dir`, `--force`) pass through to
`install.sh` unchanged.

`package.json` now declares `bin.opencode-sdlc-wizard → cli/bin/opencode-sdlc-wizard.js`
and adds `cli/` to the published `files[]`. Verified via `npm pack
--dry-run` that the CLI ships in the tarball.

### Tests

- `tests/test-cli.sh` — 10 tests: bin executable, CLI parses, package.json
  declarations correct, `--help` / `--version` / unknown subcommand,
  `init --target-dir` does install, `init --dry-run` leaves target
  untouched, `npm pack --dry-run` includes the CLI.

**Total: 123 tests, all green** (68 bundle + 11 plugin + 13 install +
21 picker + 10 CLI).

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

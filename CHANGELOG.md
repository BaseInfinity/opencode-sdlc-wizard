# Changelog

All notable changes to opencode-sdlc-wizard.

## [0.8.7] - 2026-05-06

### Fixed — cross-model-review SKILL.md provider drift + stale DeepSeek price

Audit-driven completion of the v0.8.0 provider rollout: this is the
third surface (after install.sh in v0.8.4 and setup-wizard SKILL.md
in v0.8.6) carrying the same drift. The Step 2 reviewer table still
recommended `togetherai/deepseek-ai/DeepSeek-V3` as the default at
`~$0.27/M` — both the model id and the price had moved.

Updates to `skills/cross-model-review/SKILL.md`:

- **Step 2 reviewer table** gains four rows for v0.8.0 providers:
  - `private_local/mlx` — Apple Silicon native (Qwen2.5-Coder-32B 4bit)
  - `hosted_oss/cerebras` — free tier, ~2000 tok/s, gpt-oss-120b /
    qwen-3-235b-a22b-instruct-2507
  - `hosted_oss/deepseek` direct — cheapest paid hosted reasoning
    (~$0.14/M cache-miss, deepseek-chat)
  - `hosted_oss/nvidia_nim` — free credits at build.nvidia.com
- **Stale Together row** kept but model bumped to `DeepSeek-V3.1`
  (current) and price callout dropped from this row (it was wrong,
  and the cheaper deepseek-direct row sits next to it now).
- **Default suggestion** no longer pins `togetherai/DeepSeek-V3`.
  Points users to `docs/cost-ladder.md` for the per-budget pick and
  names three common defaults (cerebras free, deepseek cheap-paid,
  ollama local).
- **Step 3 examples** now show two paths — the free-tier Cerebras
  default and the cheapest-paid DeepSeek-direct path. Old Together
  example removed.

### Tests

- `test-doc-templates.sh` adds two gates against
  `cross-model-review/SKILL.md`:
  - Each v0.8.0 provider (cerebras / deepseek / nvidia_nim) appears
    as a Step 2 table row OR a Step 3 `--reviewer-provider` flag —
    avoids coincidental matches on legacy model names like
    `deepseek-coder-v2:16b`.
  - Stale `~$0.27/M` DeepSeek price string must not reappear.
- 27/27 doc-template tests green (was 25/25).
- Full suite: 299/11 (was 297/11).

## [0.8.6] - 2026-05-06

### Fixed — sibling-wizard awareness + setup-wizard skill provider drift

Two issues in the same release because they share a root cause: **drift
between v0.8.0's expanded picker and the surfaces that describe it**.

**Sibling-wizard awareness in install.sh.** Caught during the
`states-project-research` consumption test where the repo already had
`claude-sdlc-wizard` installed. `install.sh` happily wrote `.opencode/`
without acknowledging the existing `.claude/` install — leaving the
user wondering whether the wizards were merging behavior or stomping
each other (they coexist; one writes `.opencode/`, the other `.claude/`).

- New detection block runs right after the version banner.
- Looks for `.claude/skills/sdlc/` or `CLAUDE_CODE_SDLC_WIZARD.md`
  (claude-sdlc-wizard) and `.codex/` (codex-sdlc-wizard).
- Prints a single-paragraph "Note: detected sibling SDLC wizard
  installation(s)" with the dirs found, then continues install.
- Non-blocking; informational only.

**Setup-wizard SKILL.md provider drift.** Same root cause as v0.8.4's
`install.sh` next-steps drift — the skill still listed the v0.2.0 tier
providers (Ollama / LM Studio / llama.cpp / vLLM, Together / Groq /
OpenRouter, Anthropic / OpenAI). Five providers added in v0.8.0 (MLX,
Cerebras, DeepSeek direct, NVIDIA NIM, Google AI Studio) were missing.

- `private_local` row gains MLX (Apple Silicon native).
- `hosted_oss` row gains Cerebras / DeepSeek direct / NVIDIA NIM,
  with a free-tier callout pointing to `docs/cost-ladder.md`.
- `proprietary` row gains Google AI Studio (Gemini, closed weights).
- Step 2 now shows the `--free-tier-first` flag inline so users see
  it without reading `--help`.

### Tests

- `test-install.sh` adds T10/T11/T12: claude-sdlc-wizard detected,
  codex-sdlc-wizard detected, fresh empty target produces no false
  sibling detection.
- `test-doc-templates.sh` adds a setup-wizard provider drift gate:
  asserts every v0.8.x picker provider + `--free-tier-first` are
  named in the SKILL.md.
- 17/17 install behavior tests green (was 14/14).
- 25/25 doc template tests green (was 24/24).
- Full suite: 297/11 (was 293/11).

## [0.8.5] - 2026-05-06

### Fixed — schema validator emits domain-mismatch hint on foreign-domain artifacts

`validate-review-artifact.js` previously printed only generic
`required field missing` errors when a research- or persuasion-domain
handoff was validated against the code-review schema. Caught during
the `states-project-research` consumption test: a pre-existing
research-review handoff with `topic` / `audience` / `stakes` produced
5 missing-required errors with no signal that the schema might just
be wrong for the artifact category.

Heuristic added to `scripts/validate-review-artifact.js`:

- After validation fails, count missing top-level required fields and
  the presence of any foreign-domain markers (`topic`, `audience`,
  `stakes`, `research_question`, `claim`, `argument`, `manuscript`,
  `paper`, `theme`, `narrative`).
- If `≥3 missing required` AND `≥1 foreign marker present`, emit a
  single `DOMAIN HINT:` line on stderr **before** the per-field error
  list. Tells the user the artifact looks like a non-code-review
  category and to check the schema choice.
- No behavior change for legit code-review artifacts (verified with
  T32: partially-filled code-review handoff produces no hint, T33:
  valid handoff with forward-compat extras still validates clean).

### Tests

- `test-review-schemas.sh` adds T31/T32/T33: foreign-domain triggers
  hint, partial code-review does not, valid extras-laden handoff
  validates without false positive.
- 33/33 review-schema tests green (was 30/30).
- Full suite: 293/11 (was 290/11).

## [0.8.4] - 2026-05-06

### Fixed — install.sh "Next steps" hint refreshed for v0.8.x picker

The post-install banner had drifted: it still printed the v0.2.0 tier
list (Ollama / LM Studio / llama.cpp / vLLM, Azure / Bedrock,
Together / Groq / OpenRouter, Anthropic / OpenAI), missing every
provider added since v0.8.0. Caught during the
`states-project-research` consumption test — fresh installs were
sending users to a stale provider menu while the real picker offered
five more options.

Fixes in `install.sh`:

- `private_local` row gains `mlx` (Apple Silicon native, v0.8.0)
- `hosted_oss` row gains `cerebras` / `deepseek` / `nvidia_nim` (v0.8.0)
- `proprietary` row gains `google_aistudio` (v0.8.0)
- New `--free-tier-first` example line so users discover the bias flag
  without reading `--help`
- Cost guidance link to `docs/cost-ladder.md` (v0.8.0) — the doc
  exists in the bundle but nothing pointed to it from the install path
- `$0 / $20 / $200` literals escaped (`\$`) — they would have been
  expanded as positional parameters and tripped `set -u` in the
  unquoted heredoc

### Tests

- `test-install.sh` adds T9: assert next-steps text mentions every
  provider the picker emits + `--free-tier-first` + `cost-ladder.md`.
  This is the regression gate so the banner can't drift again.
- 14/14 install behavior tests green (was 13/13).
- Full suite: 290/11 (was 289/11).

## [0.8.3] - 2026-05-06

### Fixed — release workflow unblocked

`tests/test-review-schemas.sh` T13/T14 asserted `fail` when live
`.reviews/handoff.json` / `.reviews/response.json` were absent, but
those files are per-cycle review scratch — `response.json` is gitignored
and CI clean checkouts never have either. Every release tag from v0.6.0
onward (v0.6.0, v0.7.0, v0.8.0, v0.8.1, v0.8.2) failed at this single
test, leaving npm pinned at **0.2.0** while local was at **0.8.2**.

Fix: T13 + T14 now use validate-if-present semantics — schema check
runs when the file exists, absent files emit a "skipped" pass.

30/30 review-schema tests green (was 29/30). All 11 test suites green.

PR #1.

---

## [0.8.2] - 2026-05-05

### Fixed — codex round-2 F3 follow-up (PARTIALLY-FIXED → HOLDS)

Codex round-2 returned 8/10 NOT_CERTIFIED with F1/F2/F4/F5 all
HOLDING but F3 PARTIALLY-FIXED: the round-1 fix only refreshed the
`$0/mo` table; three more `llama-3.3-70b` Cerebras references
remained later in `docs/cost-ladder.md` at lines 122, 157, 173.

v0.8.2 finishes F3:

- `cost-ladder.md:122` ($20/mo Reviewer slot) — split Cerebras + Groq
  paths: Cerebras → `gpt-oss-120b`, Groq → `llama-3.3-70b-versatile`
  (Groq still catalogs the Llama 3.3 model under the `-versatile`
  suffix; Cerebras dropped it)
- `cost-ladder.md:157` ($200/mo CI-gate slot) — same split
- `cost-ladder.md:173` (per-job picker, "Routine fix" row) — Cerebras
  example now `gpt-oss-120b` or `qwen-3-235b-a22b-instruct-2507`
- `cost-ladder.md:177` (per-job picker, "CI gating" row) — added
  parenthetical noting Groq still ships Llama 3.3 70B but Cerebras
  doesn't — important context since both providers were lumped
  together in the original

Untouched (intentionally legitimate references):
- Line 27: capability-floor table — generic class example
- Line 54: Groq's `llama-3.3-70b-versatile` — actual current model
- Lines 66, 212: calibration-history callouts about the round-1
  catch — kept as the audit trail

### Tests

No test changes — doc-only fix. Suite still 289/11 green.

## [0.8.1] - 2026-05-05

### Fixed — codex round-1 cross-model review (5 findings, all addressed)

v0.7.0 + v0.8.0 shipped without external review. Codex xhigh round-1
returned 6/10 NOT_CERTIFIED with 5 actionable findings. v0.8.1 fixes
all five.

**F1 (P1)** — `scripts/detect-backends.sh:140`. Privacy-first cascade
emitted `hosted_oss/google_aistudio` while configurator only had
`proprietary/google` — followup `--tier hosted_oss --provider
google_aistudio` would fail "unsupported tier/provider". Fix: deleted
the wrong-tier line; the proprietary fallthrough at line 143 was
already correct. Both cascades now consistently put Google in
proprietary tier.

**F2 (P1)** — Detector accepted `NIM_API_KEY`/`GEMINI_API_KEY` as
alternates for `NVIDIA_API_KEY`/`GOOGLE_API_KEY`, but the configurator
hardcoded the canonical names in `{env:NAME}` references. A user with
only the alternate set got a "successfully configured" backend that
silently failed auth at runtime. Fix: dropped alternate support
entirely. Canonical names only — `NVIDIA_API_KEY` for NVIDIA NIM,
`GOOGLE_API_KEY` for Google AI Studio. JSON output `envs: [..]` array
collapsed to `env: "NAME"` singular for shape consistency.

**F3 (P1)** — `docs/cost-ladder.md` recommended Cerebras
`llama-3.3-70b` (not in current Cerebras catalog) and Gemini
`gemini-2.0-flash` (deprecated, June 2026 shutdown). Fix: updated
$0/mo path to current valid IDs (`qwen-3-235b-a22b-instruct-2507` /
`gpt-oss-120b` / `gemini-2.5-flash`). Added a "Verifying current model
IDs" callout block with live links to each provider's catalog. Added
per-provider calibration history to the closing notes section.

**F4 (P2)** — DeepSeek price quoted `~$0.27/M`, current is `~$0.14/M`
cache-miss. Fixed inline + added cache-hit qualifier to the calibration
notes.

**F5 (P2)** — `scripts/validate-review-artifact.js:133` only handled
`additionalProperties === false`, ignored schema-valued
`additionalProperties` used in the schemas for
`verification_state.test_counts`. Bad values like
`{"bad":"not-int","negative":-1}` validated successfully. Fix: added
object-schema branch — extra properties now recursively validate
against the addProps schema. Live `.reviews/*.json` artifacts still
pass; bad test_counts now fail with type/minimum errors.

### Tests

- `test-backend-picker.sh` 29 → 31: T29 (Google in proprietary tier
  both cascades), T30 (alt env names not honored)
- `test-review-schemas.sh` 28 → 30: T29 (schema-valued addProps
  enforced), T30 (positive case)
- T21 in picker updated to use `GOOGLE_API_KEY` instead of
  `GEMINI_API_KEY`

**Total: 289 tests across 11 suites** (was 285 in v0.8.0).

### Dogfood

Schemas validated their own review artifacts: `.reviews/handoff.json`
and `.reviews/response.json` for the v0.7-v0.8-001 review both
validate against the v0.7.0 schemas. Conditional validation fired —
all five findings are `status: FIXED` with `fix_summary` +
`fix_locations` populated.

## [0.8.0] - 2026-05-05

### Added — free-tier-first cascade + 5 new providers + cost ladder doc

The wizard's privacy-first cascade has always recognized that local
beats hosted beats proprietary on data sovereignty. v0.8.0 adds the
orthogonal axis: **cost**. New `--free-tier-first` flag on
`detect-backends.sh` biases recommendations toward providers with
generous free tiers (NVIDIA NIM credits, Cerebras free, Groq free
daily, Google AI Studio 1500 req/day) before paid hosted/proprietary.
Local tier still wins both cascades — it's both privacy-max AND free.

**Five new providers** in detector + configurator:

- **Cerebras** (`hosted_oss`) — fastest hosted inference (~2000 tok/s
  on Llama 3.3 70B), free tier resets daily. `CEREBRAS_API_KEY`.
- **DeepSeek direct** (`hosted_oss`) — cheapest path to DeepSeek-V3.1
  / R1 (~$0.27/M in vs ~$0.50 via OpenRouter). `DEEPSEEK_API_KEY`.
- **NVIDIA NIM** (`hosted_oss`) — generous free credits at
  build.nvidia.com, hosts most OSS models. Accepts either
  `NVIDIA_API_KEY` or `NIM_API_KEY`.
- **Google AI Studio** (`proprietary` — Gemini is closed weights) —
  1M-context Gemini 2.0 Flash with 1500 req/day free quota. Accepts
  `GOOGLE_API_KEY` or `GEMINI_API_KEY`.
- **MLX** (`private_local`) — Apple Silicon native inference,
  fastest local on M-series Macs. `mlx_lm.server` defaults to
  127.0.0.1:8080.

**`docs/cost-ladder.md`** — concrete budget map. $0/mo (free tiers
only), $0/mo local-only (hardware capex), $20/mo (one premium sub +
free for the rest), $200/mo (multi-agent CI loops). Per-job picker
table — routine fix vs long-context refactor vs security audit vs CI
gating each have a different right answer. Ships in the npm tarball
via `files[]` "docs/" addition.

### Changed

- `detect-backends.sh` JSON shape grew: `private_local.mlx`,
  `hosted_oss.{cerebras,deepseek,nvidia_nim}`,
  `proprietary.google_aistudio`. Existing fields unchanged
  (forward-compatible — new keys won't break old consumers).
- `configure-backend.sh` PROVIDER_ALIASES gained
  `cerebras→cerebras`, `deepseek→deepseek`, `nvidia_nim→nvidia`,
  `google_aistudio→google`, `gemini→google`, `mlx→mlx`. Each has a
  matching fragment that emits the right `baseURL` + `apiKey` env
  reference + custom-provider `models: { [model]: {} }` block (so
  `opencode run` resolves the pin without ProviderModelNotFoundError).
- `--free-tier-first` flag on `detect-backends.sh` (or
  `DETECT_FREE_TIER_FIRST=1` env) reorders recommendation cascade to
  prefer free providers in the hosted bucket.
- README banner bumped + cost-ladder.md cross-link added.
- `package.json` `files[]` adds `docs/` so `cost-ladder.md` ships in
  the npm tarball.

### Tests

- `tests/test-backend-picker.sh` 21 → 29 tests: detector picks up
  cerebras / deepseek / nvidia_nim / google_aistudio via env;
  `--free-tier-first` changes cascade ordering; configure-backend
  emits correct fragments for each new provider (Cerebras + DeepSeek +
  NVIDIA NIM + Google AI Studio + MLX); `nvidia_nim` and
  `google_aistudio` aliases map to canonical `nvidia` / `google`
  provider IDs.
- `tests/test-doc-templates.sh` 17 → 24 tests: cost-ladder.md exists +
  has the load-bearing sections ($0/mo, $20/mo, $200/mo, capability
  floor, hybrid pattern); `package.json files[]` includes `docs/`.

**Total: 285 tests across 11 suites** (73 + 11 + 13 + 29 + 10 + 10 +
26 + 51 + 10 + 24 + 28).

### Why this matters

Two complaints surface most often when users evaluate the wizard:
(1) "is it actually OSS-only or can I use it with Claude/GPT too?"
and (2) "what does this actually cost to run?" v0.7.0 punted on (2);
v0.8.0 makes the answer concrete with the cost ladder doc + the
free-tier-first cascade. The wizard is **any-backend by design** —
the OSS tier is a differentiator vs the Claude/Codex siblings (those
lock you in), not a requirement. Hybrid coder/reviewer (ceiling
model coder + free-tier reviewer) is the dominant pattern for cost
optimization without losing rigor.

## [0.7.0] - 2026-05-05

### Added — JSON Schemas for review artifacts + zero-dep validator

Codifies the structures the wizard has been hand-writing across review
rounds. The `.reviews/handoff.json` and `.reviews/response.json` shapes
were previously implicit — every reviewer + every consumer had to infer
them. v0.7.0 makes both shapes explicit + machine-checkable.

**`templates/schemas/handoff.schema.json`** — JSON Schema (draft-07) for
the handoff artifact: `review_id`, `status` (PENDING_REVIEW / IN_REVIEW
/ CERTIFIED / NOT_CERTIFIED), `round`, `mission`, `success`, `failure`,
`review_instructions`, plus optional `files_changed`, `verification_state`
with `tests_green` + `test_counts`, `preflight_path`, `response_path`,
`artifact_path`. Permissive `additionalProperties: true` for forward
compat — extra fields don't break validation.

**`templates/schemas/response.schema.json`** — Schema for the response
artifact: top-level `responses[]` array with per-finding shape
(`finding_id`, `severity` matching `^P[0-2]( \(.*\))?$` to allow
parenthetical context, `title`, `claim`, `status`). Conditional
validation enforces: `FIXED` requires `fix_summary` + `fix_locations`;
`REJECTED` / `WONT_FIX` requires `rejection_reason`. Pattern-key
support for `recheck_instructions_for_round_N`.

**`scripts/validate-review-artifact.sh`** + companion `.js` — zero-dep
validator (pure node, no `npm install`). Implements the draft-07 subset
the schemas use: `type`, `required`, `properties`, `enum`, `pattern`,
`minLength`, `minimum`, `items`, `$ref` (#/definitions/*),
`patternProperties`, `allOf` with `if`/`then`, `const`, `definitions`.
Exit codes: `0` valid / `1` invalid (errors with jsonpath + reason on
stderr) / `2` usage / missing-file / unparseable JSON.

Both schemas + validator install to `.opencode/schemas/` and
`.opencode/scripts/` respectively. Live `.reviews/handoff.json` and
`.reviews/response.json` (round-2 artifacts from v0.2.0) validate
against the schemas — the schemas were derived from these artifacts so
they're guaranteed compatible with prior rounds.

### Updated — skills consume the schemas

**`cross-model-review` SKILL.md** — new Step 1.5 validates handoff +
response against the schemas before sending the prompt to the reviewer.
A malformed handoff wastes reviewer tokens and produces a confused
review; validation is fast (zero deps, sub-100ms) and fails fast with
specific jsonpath + reason for every error.

**`setup-wizard` SKILL.md** — Step 4 (Generate) now mentions the
schemas as the canonical shape for review artifacts. No setup work
required (schemas auto-install); the skill points consumers at them
when they create their first review artifact.

### Drift-test extension

`tests/test-bundle-drift.sh` extended to:
- Include `scripts/*.js` companions in the "every script ships in
  install.sh" check (T7) — without this, a `.js` file added to scripts/
  but forgotten in install.sh would silently never reach consumers.
- New T12: every `templates/schemas/*.schema.json` must be shipped by
  install.sh — same drift-class for the schemas dir.

### Tests

- `tests/test-review-schemas.sh` — 28 tests covering: schemas exist +
  parse + declare draft-07; validator script exists + executable +
  prints usage on `--help` + handles missing-file/bad-JSON gracefully;
  live `.reviews/*.json` artifacts validate; negative cases for missing
  required fields, bad enum, wrong type, FIXED-status missing
  `fix_summary`/`fix_locations`, REJECTED-status missing
  `rejection_reason`, P3 severity (pattern violation), parenthetical
  P0 severity (allowed), `recheck_instructions_for_round_N` pattern
  keys; bundle-test that install lands schemas + validator at the
  expected paths and the installed pair validates the live handoff
  end-to-end.

**Total: 270 tests across 11 suites** (73 + 11 + 13 + 21 + 10 + 10 +
26 + 51 + 10 + 17 + 28). bundle-drift grew from 48 → 51 (`.js`
inclusion + 2 schema-shipped checks).

### Changed

- `install.sh` REQUIRED_SOURCES + declare_target add the validator
  pair (`.sh` + `.js`) and both schemas.
- `package.json` `description` mentions JSON Schemas; `test` script
  adds the new suite. `files[]` already includes `scripts/` and
  `templates/`, so the new files publish without further changes.

### Why this matters

The handoff/response artifacts have been the load-bearing
hand-shake between the implementing agent and the reviewer all
session. Locking the shape down means: (1) `cross-model-review` skill
fails fast on bad handoffs instead of producing confused reviews,
(2) the `ditto` cross-host migrator (when it lands at v0.1.0) can
parse + transform these artifacts safely, (3) any future CI tooling
gating release on a CERTIFIED status can validate the artifact
shape with zero `npm install`. Forward-compat is preserved — extra
keys are allowed, so older artifacts validate against the new schema
without retrofit.

## [0.6.0] - 2026-05-05

### Added — `SDLC.md` and `ARCHITECTURE.md` templates

Closes the doc-template gap. v0.4.0 shipped four `TESTING.md` domain
templates; setup-wizard skill referenced `SDLC.md` and `ARCHITECTURE.md`
generation but had no template, so each consumer reinvented the wheel.

**`templates/sdlc.md`** — SDLC baseline (plan→TDD→self-review→cross-
model-review), confidence levels (HIGH / MEDIUM / LOW), commands
table, cross-cutting rules. References both the codex flow and the
v0.3.1 OSS-tier `cross-model-review` skill so consumers know they
have a vendor-neutral path. Includes the `<!-- SDLC Wizard Version
-->` metadata comment so `update-wizard` skill can detect drift.

**`templates/architecture.md`** — System overview / components /
environments / deployment / decisions log. Seeds the decisions log
with one example entry (the `Bun.spawnSync` vs `execFile` decision
from v0.2.0 — illustrates the format and gives consumers a real
reference).

Both install at `.opencode/templates/` so the setup-wizard skill
copies them with project-specific substitutions during bootstrap.

### Tests

- `tests/test-doc-templates.sh` — 17 tests: templates exist, contain
  load-bearing sections (Plan/TDD/self-review/Confidence/version-stamp
  for SDLC.md; overview/Environments/decisions for ARCHITECTURE.md),
  SDLC.md invokes `skill({ name: "sdlc" })`, install delivers both
  to `.opencode/templates/`, setup-wizard skill references both
  template paths.

**Total: 238 tests across 10 suites** (73 + 11 + 13 + 21 + 10 + 10 +
26 + 47 + 10 + 17).

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

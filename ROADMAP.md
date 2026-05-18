# Roadmap

Public roadmap for `opencode-sdlc-wizard`. Items are ordered by current
priority but may shuffle as real-world use surfaces friction.

## v0.2.0 — shipped 2026-05-04

- ✅ Privacy-first four-tier backend picker (`scripts/{detect,configure}-backend.sh`)
- ✅ Live E2E reliability fixes (session.created race + Bun.spawnSync)
- ✅ Codex round-3 cross-model review CERTIFIED 9/10
- ✅ 113/113 tests across 4 suites
- ✅ npm publish flow + `release.yml` automation
- ✅ Companion docs: PRIVACY.md, RELEASING.md, HANDOFF.md addendum

See [CHANGELOG.md](CHANGELOG.md#020---2026-05-04) for the full release
notes.

## v0.3.0 — `npx opencode-sdlc-wizard init` CLI — shipped 2026-05-04

- ✅ `bin` entry in package.json → `cli/bin/opencode-sdlc-wizard.js`
- ✅ Node wrapper that shells out to `install.sh` for the real run
- ✅ Wrapper-level `--dry-run` previews bundle without writing
- ✅ `--target-dir` / `--force` pass through to `install.sh`
- ✅ 10 CLI tests in `tests/test-cli.sh` (123/123 total across 5 suites)
- ✅ README updated to lead with `npx opencode-sdlc-wizard init`

## v0.3.1 — `cross-model-review` skill (OSS reviewer) — shipped 2026-05-04

- ✅ `skills/cross-model-review/SKILL.md` — adaptive skill picks reviewer + runs through opencode
- ✅ `scripts/cross-model-review.sh` — non-interactive wrapper, alias-aware
- ✅ Provider alias resolution shared with `configure-backend.sh`
- ✅ 10 tests via stubbed opencode (138 total across 6 suites)
- ✅ CHANGELOG + skill recommendations documented

Live E2E pending: needs a configured OSS provider (Groq free tier,
local Ollama 30B+ model, or Together/OpenRouter key). Stub tests cover
the script logic; live E2E proves the wiring against a real reviewer.

## v0.4.0 — domain-adaptive TESTING.md templates — shipped 2026-05-04

- ✅ 4 templates: firmware / data-science / cli / web
- ✅ Setup-wizard skill detects domain from concrete signals
- ✅ Templates ship at `.opencode/templates/testing/<domain>.md`
- ✅ 26 tests in `test-domain-templates.sh` (164 total across 7 suites)

## v0.5.0 — `check` subcommand + bundle-drift extension — shipped 2026-05-05

- ✅ `npx opencode-sdlc-wizard check [--json] [--target-dir]` — symmetric
  to `init`; rc=0 (current) / rc=1 (behind) / rc=2 (not installed)
- ✅ `scripts/check-updates.sh` — backs the CLI; also installable at
  `.opencode/scripts/` so skills + hooks can invoke directly
- ✅ Fixed hook bug: `npm view agentic-sdlc-wizard` → `opencode-sdlc-wizard`
- ✅ Extended drift tests to cover hooks (no parent-package executable
  refs, mirror byte-equality)
- ✅ 221 tests across 9 suites (was 192/8 in v0.4.1)

## v0.6.0 — `SDLC.md` + `ARCHITECTURE.md` templates — shipped 2026-05-05

- ✅ `templates/sdlc.md` — SDLC baseline + workflow phases + confidence
  levels + cross-cutting rules; references both codex + cross-model-review
- ✅ `templates/architecture.md` — overview / components / environments /
  deployment / decisions log
- ✅ install delivers both at `.opencode/templates/`
- ✅ setup-wizard skill references both templates
- ✅ 17 tests in `test-doc-templates.sh` (238 total across 10 suites)

## v0.7.0 — JSON schemas for review artifacts + zero-dep validator — shipped 2026-05-05

- ✅ `templates/schemas/handoff.schema.json` — draft-07 schema for the
  handoff artifact (review_id / status / round / mission / success /
  failure / review_instructions + optional fields)
- ✅ `templates/schemas/response.schema.json` — draft-07 schema for the
  response artifact, including conditional validation (FIXED requires
  fix_summary+fix_locations; REJECTED requires rejection_reason) and
  patternProperty support for `recheck_instructions_for_round_N`
- ✅ `scripts/validate-review-artifact.sh` + `.js` — zero-dep node
  validator (no `npm install` to consumers); handles draft-07 subset
  the schemas use including $ref + allOf if/then + const
- ✅ install lands schemas at `.opencode/schemas/` + validator at
  `.opencode/scripts/`
- ✅ `cross-model-review` skill new Step 1.5 — validate before sending
  the prompt; `setup-wizard` skill mentions schemas in Step 4
- ✅ Drift-test extension: scripts/*.js + templates/schemas/* coverage
- ✅ 28 tests in `test-review-schemas.sh` (270 total across 11 suites)

## v0.8.0 — free-tier-first cascade + 5 providers + cost ladder — shipped 2026-05-05

- ✅ `--free-tier-first` flag on `detect-backends.sh` (and
  `DETECT_FREE_TIER_FIRST=1` env) biases cascade toward free providers
- ✅ 5 new providers wired through detector + configure-backend:
  Cerebras, DeepSeek direct, NVIDIA NIM, Google AI Studio (Gemini),
  MLX (Apple Silicon native)
- ✅ `docs/cost-ladder.md` — concrete $0 / $20 / $200 monthly budget
  paths with per-job picker table
- ✅ README bumped + cross-links to cost ladder
- ✅ package.json files[] adds docs/ so cost ladder ships in tarball
- ✅ 8 new picker tests + 7 new doc-template tests (285 total / 11 suites)

## v0.8.4–v0.8.9 — drift family closure — shipped 2026-05-12

Cleanup sweep after v0.8.0 added 5 new picker providers + the cost
ladder doc. Five surfaces drifted past the v0.8.0 picker; each was
closed with a regression gate.

- ✅ v0.8.4 — `install.sh` "next steps" hint refreshed for v0.8.x picker
- ✅ v0.8.5 — validator emits `DOMAIN HINT` on foreign-domain artifacts
- ✅ v0.8.6 — sibling-wizard awareness (.claude/, .codex/) + setup-wizard SKILL.md drift
- ✅ v0.8.7 — cross-model-review SKILL.md drift + stale DeepSeek price (~$0.27/M → ~$0.14/M)
- ✅ v0.8.8 — AGENTS.md + PRIVACY.md tier-table + walkthrough drift
- ✅ v0.8.9 — `cross-model-review.sh` wrapper alias parity with `configure-backend.sh`
  (only runtime bug in the family — `nvidia_nim`/`google_aistudio` silently broke;
  caught by codex pre-ship review)
- ✅ 305 tests across 11 suites

## v0.9.0 — `pick` subcommand (one-shot detect → configure) — shipped 2026-05-12

Codex's direction call: collapse picker UX before Mixed-mode. The
two-step `detect → configure` workflow becomes
`npx opencode-sdlc-wizard pick [--free-tier-first] [--tier T] [--provider P]`.

- ✅ `scripts/pick-backend.sh` — orchestrator with PATH-first script lookup
- ✅ Canonical default-model map per tier/provider (14 entries — single source of truth)
- ✅ CLI subcommand wired in `cli/bin/opencode-sdlc-wizard.js`
- ✅ `install.sh` ships pick at `.opencode/scripts/pick-backend.sh`
- ✅ 25 new tests in `test-pick.sh` (333 total / 12 suites)
- ✅ Default-model map drift gate (T12) — every v0.8.x picker provider must have a default

## v0.9.1 — Ollama default Qwen 2.5 → Qwen 3 — shipped 2026-05-12

Community-patterns research surfaced that Qwen3-Coder is the most-cited
local default in May-2026 shared configs. Single default-model bump
verified against the live ollama.com tag list before shipping.

- ✅ `private_local/ollama` default: `qwen2.5-coder:32b` → `qwen3-coder:30b`
- ✅ All mirroring doc surfaces updated (install.sh, PRIVACY.md, README, AGENTS.md, cost-ladder)
- ✅ Other community-flagged swaps (Groq, OpenAI, Gemini, DeepSeek) deferred per-provider until each lives in a verifiable catalog

## v0.10.0 — Mixed-Mode (per-agent model routing) — shipped 2026-05-17

The pattern community research called out as the May-2026 baseline:
11/15 surveyed `opencode.json` files route review work to a different
model than build work. v0.10.0 makes the split a one-flag-pair operation.

- ✅ `configure-backend.sh` learns `--reviewer-tier T --reviewer-provider P --reviewer-model M` (all-or-nothing triplet)
- ✅ Writes `agent.review.model` plus reviewer's provider block (deep-merged with coder's; same-provider collapses to one block)
- ✅ Reviewer side uses same `PROVIDER_ALIASES` map → canonical IDs only in the written config
- ✅ `pick` forwards reviewer flags; `--reviewer-model` optional (filled from canonical default-model map, same lookup as coder)
- ✅ Default-model lookup factored into a `default_model_for()` function — single source of truth used for both sides
- ✅ 8 new tests (T31–T34 in test-backend-picker, T15–T18 in test-pick); 341 total across 12 suites
- ✅ `docs/cost-ladder.md` $20/mo hybrid example shows the new one-shot invocation
- ✅ `cross-model-review.sh` wrapper unchanged — Mixed-Mode is the standing config; wrapper is the explicit invocation

Planner / docs / test-writer agent routing deferred to v0.10.1+ — `pick`
gains `--planner-*` / `--docs-*` flags as each pattern is validated.

## v0.10.1 → v0.13.1 — community-signal sprint — shipped 2026-05-17 / 2026-05-18

Once `pick` existed, the May-17 community-patterns research surfaced a
clear queue: 5/6 of the highest-signal community patterns ranked above
50% adoption in surveyed `opencode.json` files. The v0.10.1–v0.13.1
arc shipped every one of them. Wizard is now **feature-complete relative
to May-2026 community signals**.

- ✅ v0.10.1 — `--sandbox-test-writer` + `--sandbox-docs` (path-scoped permission blocks)
- ✅ v0.10.2 — `--planner-*` (Mixed-Mode for the plan agent; community's #1 most-overridden agent at 57%)
- ✅ v0.10.2 — default-model bumps: openai → `gpt-5.3-codex`, google → `gemini-3.1-pro`
- ✅ v0.10.3 — default-model bumps: deepseek → `deepseek-v4-flash`, groq → `gpt-oss-120b`
- ✅ v0.10.4 — `--small-*` for top-level `small_model` (35–40% community adoption)
- ✅ v0.10.5 — `--sandbox-plan` (categorical tool denial via `agent.plan.tools.{write,edit,patch}=false`)
- ✅ v0.10.6 — cost-ladder.md recalibration (model IDs + Z.AI quarterly pricing)
- ✅ v0.11.0 — Z.AI GLM Coding Plan as proprietary provider (post-Anthropic-OAuth-ban migration target)
- ✅ v0.11.1 — `--coder-temp` / `--planner-temp` / `--reviewer-temp` per-agent temperatures
- ✅ v0.11.2 — full security agent: `--security-*` triplet + `--security-temp` + `--sandbox-security`
- ✅ v0.12.0 — new `managed` tier; OpenCode Zen (`opencode` provider; 40+ models incl. free tier)
- ✅ v0.13.0 — new `subscription` tier; GitHub Copilot Pro+ (first OAuth-based provider, no env-var)
- ✅ v0.13.1 — PRIVACY.md tier walkthroughs updated for the six-tier reality

**Wizard surface as of v0.13.1:**

- **6 tiers**: `private_local`, `enterprise`, `hosted_oss`, `managed`, `proprietary`, `subscription`
- **17 providers** with canonical default-model entries
- **5 first-class agents**: coder/build, small_model, planner (plan), reviewer (review), security
- **3 sandbox shapes**: path-scoped permission.write (test-writer, docs), categorical tools-denial (plan, security)
- **407 tests across 12 suites**
- **15 tagged releases this sprint** (v0.8.4 → v0.13.1)

## v0.13.2+ candidates (post-sprint backlog, no community-research backing)

These are speculative — they have no direct community-signal evidence
behind them. Either dogfood feedback or a fresh research pass should
drive what's next.

- **Auto-nudge integration**: `instructions-loaded-check.sh` hook
  delegates to `check-updates.sh` instead of duplicating the version-
  check logic. DRY refactor; drift prevention only.
- **NIM 1M-context emphasis in cost-ladder**: per May-2026 research,
  NVIDIA NIM free tier has 1M-token context on DeepSeek V4 with
  RPM-only limits — bigger than Cerebras's 8K-64K free cap. Doc patch.
- **OPENCODE_SDLC_WIZARD.md master doc**: equivalent of parent's
  4506-line CLAUDE_CODE_SDLC_WIZARD.md. Heavier lift; defer until
  consumer feedback says it's needed.
- **Schema versioning + migration**: when v0.7.0 schemas need a
  breaking change, add `$schema_version` field + a migrator the
  validator runs through. Defer until first breaking change is needed.

## Phase B — backend matrix proof

Status: deferred from v0.1.0. Triggered by maintainer authorization.

Run paired E2E SDLC scenarios (plan → TDD → self-review) against:

| Tier | Backend | Floor model |
|------|---------|--------------|
| Local | Ollama / Qwen2.5-Coder-32B (16-24GB VRAM class) | Floor |
| Enterprise | Azure OpenAI tenant | Floor |
| Hosted OSS | Together / Groq / OpenRouter (Qwen-Coder, DeepSeek-V3) | Floor |
| Anthropic baseline | Opus 4.7 max | Ceiling |

Score each against parent's tier-2 evaluation rubric (10-point criteria,
5 trials, 95% CI). Document which backends hold SDLC compliance and
which degrade. Capability-floor note still applies: small models
(7-13B) will fail and that's a result, not a bug.

## Phase C — hardware scout for local tier

Status: deferred. Triggered if Phase B needs hardware.

Test gaming laptop + Windows laptop first (zero spend). If 16-24GB
VRAM bar isn't met, evaluate $200/$300/$400 rig OR cloud-GPU rental.

## Cross-cutting — XDLC ditto migrator

Status: roadmapped, not in this repo's scope.

A separate cross-host migrator (`ditto`) is roadmapped at
[`xdlc/docs/ditto-roadmap.md`](https://github.com/BaseInfinity/xdlc/blob/main/docs/ditto-roadmap.md)
to automate future ports between siblings. v0.1.0 trigger: when
sibling #5 starts (or upstream `claude-sdlc-wizard` ships a release
that needs syncing across the three existing siblings).

The first transform set ditto v0.1.0 will codify is the
`claude-sdlc-wizard → opencode-sdlc-wizard` port we hand-applied for
v0.2.0 — captured in `HANDOFF.md` v0.2.0 addendum + the F1-F6 + E2E
findings tables in `.reviews/response.json`. Those are effectively the
unstructured form of `xdlc/docs/ports/claude-to-opencode.md`.

When `ditto v0.1.0` ships, its first regression test will harvest
those tables, scan + diff the two repos, and assert the auto-generated
transform table matches what we wrote down by hand.

## How to consume this roadmap

- Open issues in [the repo](https://github.com/BaseInfinity/opencode-sdlc-wizard/issues)
  to bid up an item or propose a new one.
- Items are not promises. Real-world use of v0.2.0 may surface
  higher-priority work that bumps these.
- `feedback` skill (privacy-first) is the canonical way to surface
  bugs / requests without scanning the repo.

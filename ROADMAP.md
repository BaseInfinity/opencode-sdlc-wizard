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

## v0.9.0+ candidates (unprioritized)

- **Mixed-mode skill**: setup-wizard could pin a coder model + a
  reviewer model in one config (today they're picked separately).
  This is the natural complement to the cost-ladder doc — automate
  the hybrid coder/reviewer pattern.
- **Auto-nudge integration**: `instructions-loaded-check.sh` hook
  delegates to `check-updates.sh` instead of duplicating the version-
  check logic. Net: one source of truth, fewer drift opportunities.
- **OPENCODE_SDLC_WIZARD.md master doc**: equivalent of parent's
  4506-line CLAUDE_CODE_SDLC_WIZARD.md. Heavier lift; defer until
  consumer feedback says it's needed.
- **Schema versioning + migration**: when v0.7.0 schemas need a
  breaking change, add `$schema_version` field + a migrator the
  validator runs through. Defer until first breaking change is needed.
- **Auto-picker tool**: pipe detect-backends → configure-backend in
  one command (`opencode-sdlc-wizard pick --free-tier-first`). The
  raw scripts work today; this is just sugar.

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

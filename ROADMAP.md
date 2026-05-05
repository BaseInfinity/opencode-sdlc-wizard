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

## What's next (v0.5.0+ candidates)

These are unprioritized — surface real demand to bid them up:

- **`update-wizard` skill enhancement**: drift detection across
  installed bundles (new feature in upstream → user nudge).
- **Codex-style structured handoff/response artifacts**: ship JSON
  schemas for `.reviews/handoff.json` + `.reviews/response.json` so
  cross-model reviews have explicit contracts.
- **Mixed-mode skill**: setup-wizard could pin a coder model + a
  reviewer model in one config (today they're picked separately).
- **Stale-skill drift test**: catch helper skills referencing
  removed/renamed scripts at install time.

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

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

## v0.3.0 candidate — `cross-model-review` skill (OSS reviewer)

Status: planned. Target after v0.2.0 sees real consumer use.

The cross-model review SDLC step today expects Codex (OpenAI gpt-5.5).
That re-introduces the vendor lock that v0.2.0 removed for the coder.
Closing the loop: a `cross-model-review` skill that runs the review
through OpenCode itself with an OSS-tier model:

- **Reviewer recommendations:** DeepSeek-V3 via Together (deep reasoning,
  ~$0.27/M input — pennies per review) or Qwen2.5-Coder-32B via Groq
  (fastest), or local Ollama Qwen2.5-Coder-32B (true zero-egress
  for air-gapped contexts).
- **Skill:** reads `.reviews/handoff.json` + `.reviews/response.json`,
  invokes `opencode run --model <chosen>` with a structured review
  prompt, writes `.reviews/latest-review.md`. Symmetric to the codex
  flow.
- **Wrapper:** `scripts/cross-model-review.sh` for non-skill / CI use.
- **PRIVACY.md addition:** the all-OSS pipeline recipe (Ollama coder +
  Ollama reviewer = zero network egress for the entire SDLC loop).

## v0.4.0 candidate — domain-adaptive expansion

Status: speculative. Triggered by real demand.

The wizard currently treats `setup-wizard` as web-API-default. Domain
detection in the parent (firmware / data-science / CLI / web)
applies here too. If `npm i opencode-sdlc-wizard` users start landing
on firmware or data-science repos, surface domain-specific TESTING.md
templates the way the parent does.

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

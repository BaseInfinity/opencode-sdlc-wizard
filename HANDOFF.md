# OpenCode SDLC Wizard — Bootstrap Handoff

> **Read this first.** This document is the brain-dump from the bootstrap session
> (2026-05-03). It tells the next Claude Code session what this repo is for,
> what's already been decided, what's left to do, and the exact order of
> operations to execute Phase A.
>
> **Purpose of this repo:** port the SDLC enforcement wizard pattern to
> [`sst/opencode`](https://github.com/sst/opencode) so users can run the full
> SDLC harness against **any model backend their privacy/compliance constraints
> allow** — not just Anthropic. Local Ollama / LM Studio / vLLM, enterprise
> Azure OpenAI / AWS Bedrock / internal gateways, hosted OSS Together / Groq /
> OpenRouter, plus the usual OpenAI / Anthropic.

## Position in the XDLC sibling family

You are sibling #4 in the family. Same wizard pattern, different agent / domain:

| Sibling | npm package | Repo | Writes to | Status |
|---------|-------------|------|-----------|--------|
| Claude SDLC | `agentic-sdlc-wizard` | [`BaseInfinity/claude-sdlc-wizard`](https://github.com/BaseInfinity/claude-sdlc-wizard) | `.claude/` | shipped, v1.64.0 (the canonical reference) |
| Codex SDLC | `codex-sdlc-wizard` | [`BaseInfinity/codex-sdlc-wizard`](https://github.com/BaseInfinity/codex-sdlc-wizard) | `.codex/` + `AGENTS.md` | shipped, v0.7.x (the closest port reference) |
| Claude GDLC | `claude-gdlc-wizard` | [`BaseInfinity/claude-gdlc-wizard`](https://github.com/BaseInfinity/claude-gdlc-wizard) | `.gdlc/` (or similar) | shipped, v0.2.x (different domain — games) |
| **OpenCode SDLC (this repo)** | `opencode-sdlc-wizard` (planned) | `BaseInfinity/opencode-sdlc-wizard` | `.opencode/` | bootstrap stage |

**Use the Codex port as your primary reference.** It's the most recent sibling,
its install pattern and hook adaptation are battle-tested, and its scope
matches yours (port, not new domain).

## Why this exists (driver context)

Two pressures created the demand:

1. **Cost / single-vendor lock-in pain.** Anthropic API credit caps repeatedly
   blocked release work in `claude-sdlc-wizard` (April 2026). Single-vendor
   lock-in is expensive and fragile.
2. **Real enterprise + privacy use cases.** Legal contexts can't send
   privileged data to cloud APIs (attorney-client privilege). Enterprises with
   work Azure OpenAI tenants want zero-retention. Air-gapped environments need
   local-only models. None of those workflows can use the Claude Code wizard.

OpenCode is the right target because it already speaks many providers out of
the box — local Ollama, LM Studio, llama.cpp, vLLM; enterprise Azure OpenAI,
AWS Bedrock, internal gateways; hosted OSS Together, Groq, OpenRouter; plus
standard OpenAI / Anthropic. **One install → user picks their backend → SDLC
enforcement still works.**

## ROADMAP scope (verbatim from claude-sdlc-wizard ROADMAP #9)

> **Phase A — port the wizard:** spawn `opencode-sdlc-wizard` sibling
> mirroring the Codex port pattern (`agentic-sdlc-wizard` writes `.claude/`,
> `codex-sdlc-wizard` writes `.codex/` + `AGENTS.md`; new sibling writes
> `.opencode/`). Map hooks → OpenCode's pre/post-tool primitives, port
> `instructions-loaded-check` + `sdlc-prompt-check` + `tdd-pretool-check` +
> `precompact-seam-check` + `model-effort-check`, port all 4 skills (SKILL.md
> is already portable per #91), non-destructive config merge in `install.sh`,
> quality tests proving hooks actually fire under OpenCode.
>
> **Phase B — backend matrix proof:** run an E2E SDLC scenario (plan → TDD
> → self-review) against at least one from each category: local (Ollama +
> Qwen-Coder or DeepSeek-Coder, 16–24GB VRAM class), enterprise gateway
> (Azure OpenAI), hosted OSS (Together/Groq). Score each against the Claude
> Code baseline; document which backends hold SDLC compliance and which
> degrade.
>
> **Capability-floor note:** "just works on every LLM" is the dream but not
> the spec — expect small local models (7–13B) to fail the full
> plan→TDD→self-review protocol (instruction-following + long-context
> reasoning + tool-use are all load-bearing). The 30B+ code-tuned class
> (Qwen-Coder, DeepSeek-Coder) is the likely local sweet spot. **A failed
> run on an undersized model is a capability result, not a port bug** — log
> it in the matrix and move on.
>
> **Phase C — hardware scout for local tier:** test gaming laptop +
> Windows laptop first (zero cost); if insufficient, evaluate $200/$300/$400
> rig or cloud-GPU rental.
>
> **Success criterion:** a user can pick their backend (local for privacy,
> Azure for enterprise, OSS-hosted for cost, Anthropic for ceiling) and get
> the same SDLC enforcement.

## What Phase A actually ships (concrete v0.1.0 scope)

This is the bounded scope you should aim for in the next session(s):

1. **Hooks ported to OpenCode primitives:**
   - `sdlc-prompt-check.sh` — emits SDLC BASELINE on every user prompt
   - `tdd-pretool-check.sh` — emits TDD reminder before Write/Edit on source files
   - `instructions-loaded-check.sh` — session-start validation of SDLC.md/TESTING.md, model/effort recommendations
   - `model-effort-check.sh` — nudges effort upgrade when behind recommended
   - `precompact-seam-check.sh` — blocks compact mid-review/mid-rebase

2. **Skills (copy verbatim — they're already portable):**
   - `skills/sdlc/SKILL.md`
   - `skills/setup/SKILL.md`
   - `skills/update/SKILL.md`
   - `skills/feedback/SKILL.md`

3. **`install.sh`** — non-destructive config merge into target repo's
   `.opencode/` (mirror Codex sibling's `install.sh` pattern, which is
   battle-tested for 6 config-merge cases including macOS sed TOML
   corruption fixes).

4. **`AGENTS.md`** at repo root (OpenCode's equivalent of CLAUDE.md? — verify
   in research checklist below).

5. **Quality tests** proving hooks actually fire under OpenCode — port the
   wizard's hook-firing tests.

6. **`README.md`** matching the sibling-family format (will eventually need
   the XDLC Ecosystem section, like `agentic-sdlc-wizard` v1.64.0).

## Research checklist — VERIFIED 2026-05-03

Implementation session verified all items below; updates marked `[x]` with
the discovered facts.

- [x] **OpenCode hook event surface — NOT Claude-style hooks. Use plugins.**
      OpenCode does not have a `.claude/settings.json`-style declarative hook
      config. The closest equivalent is the **plugin system**: JS modules at
      `.opencode/plugins/*.js` (project-local) or
      `~/.config/opencode/plugins/` (global), automatically loaded at
      startup. Plugin entry point:
      ```javascript
      export const MyPlugin = async ({ project, client, $, directory, worktree }) => {
        return { /* event handlers */ }
      }
      ```
      Plugins receive Bun's shell API (`$`), so they can shell out to bash
      hooks. **Relevant events for port:**
      - `session.created` ← Claude's `SessionStart`
      - `tool.execute.before` ← Claude's `PreToolUse`
      - `tool.execute.after` ← Claude's `PostToolUse`
      - `experimental.session.compacting` ← Claude's `PreCompact`
      - **No direct `UserPromptSubmit` analog.** Workaround: put SDLC
        BASELINE content in `AGENTS.md` (loaded once per session) instead
        of repeating it on every prompt. Loses per-prompt nudge cadence
        but the content survives.
      Source: https://opencode.ai/docs/plugins/
- [x] **`.claude/settings.json` equivalent = `opencode.json` (or `.jsonc`)**
      Top-level keys include `model`, `agent`, `command`, `permission`,
      `compaction`, `mcp`, `plugin`, `instructions`. Schema:
      `https://opencode.ai/config.json`. **No `hooks` key** — confirmed via
      docs/config/. Hooks-equivalent goes through `plugin`.
- [x] **Skill system — DIRECTLY COMPATIBLE.** OpenCode discovers skills at
      multiple paths and walks up from cwd to git worktree root:
      - Project-local: `.opencode/skills/<name>/SKILL.md`
      - Global: `~/.config/opencode/skills/<name>/SKILL.md`
      - **Claude-compatible: `.claude/skills/<name>/SKILL.md`** ← reads ours
      - Agent-compatible: `.agents/skills/<name>/SKILL.md`
      SKILL.md frontmatter convention is identical (YAML, `name` +
      `description` required, lowercase-alphanumeric-with-hyphens name).
      **Implication:** our 4 skills port verbatim — install at
      `.opencode/skills/` (canonical) and the existing parent-wizard
      skills also work via `.claude/skills/` if user dual-installs.
      Source: https://opencode.ai/docs/skills/
- [x] **Compact event exists — `experimental.session.compacting`.** Marked
      experimental, but it's there. Our `precompact-seam-check.sh` adapts
      via the plugin shim.
- [x] **AGENTS.md is the primary instruction file.** Order of precedence:
      (1) `AGENTS.md` then `CLAUDE.md` walking up from cwd; (2) global
      `~/.config/opencode/AGENTS.md`; (3) `~/.claude/CLAUDE.md` fallback
      for Claude Code migration. **Decision: ship AGENTS.md as the primary
      instruction file**, matching Codex sibling. CLAUDE.md compat is a
      free bonus from OpenCode's fallback logic.
- [x] **Backend selection.** `opencode.json` has top-level `model` key plus
      `provider` config. Setup wizard prompts for backend and writes the
      appropriate `model` value (e.g., `"anthropic/claude-opus-4-7"`,
      `"ollama/qwen-coder"`). Phase A ships the prompt + writes the value;
      backend matrix proof is Phase B.
- [x] **Custom commands.** OpenCode has a slash-command system at
      `.opencode/commands/*.md` (filename = command name) with `template`
      / `description` / `agent` / `model` config. Optional for Phase A —
      not strictly needed since skills cover the workflow.

## Order of operations (next session: do these in order)

1. **Read this entire `HANDOFF.md` plus the README and the `CLAUDE.md` in
   this repo.** They're terse; should take 5 minutes.

2. **Skim the Codex sibling** as your reference port. Specifically read:
   - `BaseInfinity/codex-sdlc-wizard/install.sh` (the 6-case merge logic)
   - `BaseInfinity/codex-sdlc-wizard/hooks/` (3 ported hooks — note how
     they adapt Claude's stdin-JSON contract to Codex's notify config)
   - `BaseInfinity/codex-sdlc-wizard/AGENTS.md` (instruction file)
   - `BaseInfinity/codex-sdlc-wizard/.github/workflows/upstream-sync.yml`
     (how the sibling stays current with the parent wizard)

3. **Skim the Claude parent** for the canonical assets you'll port:
   - `BaseInfinity/claude-sdlc-wizard/hooks/` (5 hooks, all bash)
   - `BaseInfinity/claude-sdlc-wizard/skills/` (4 SKILL.md files)
   - `BaseInfinity/claude-sdlc-wizard/cli/templates/settings.json`
     (the `.claude/settings.json` template the install merges in)
   - `BaseInfinity/claude-sdlc-wizard/CLAUDE_CODE_SDLC_WIZARD.md`
     (the master wizard doc — likely don't port verbatim, write an
     `OPENCODE_SDLC_WIZARD.md` adapted for OpenCode users)

4. **Execute the research checklist above.** Update this HANDOFF.md as you
   verify each item — turn the `[ ]` into `[x] (verified: <fact>)` so the
   next future-session reader has the answers.

5. **Run `/setup-wizard` in this repo** if appropriate — let the
   wizard set up its own SDLC enforcement on this sibling. (You're
   dogfooding Claude Code's SDLC wizard while building OpenCode's SDLC
   wizard. Meta but correct.)

6. **Port hooks one at a time, TDD-style.** For each:
   - Read the original (`claude-sdlc-wizard/hooks/<name>.sh`)
   - Write the OpenCode-adapted version + a quality test that asserts
     it fires correctly under OpenCode
   - Verify with mutation test (neuter the hook, confirm test goes red)
   - Commit individually so each port is reviewable

7. **Port skills verbatim** — they're already portable per ROADMAP #91.

8. **Write `install.sh`** following the Codex pattern.

9. **Cross-model review with Codex** (per the parent repo's process:
   `codex exec -c 'model_reasoning_effort="xhigh"' ...`) on the whole port
   before tagging v0.1.0.

10. **Tag v0.1.0**, publish to npm as `opencode-sdlc-wizard`, open mirror
    issues in the other 3 siblings to add OpenCode to their Ecosystem
    sections.

## Decisions deferred to the maintainer (don't choose without asking)

These are real architecture / spend decisions. The next session should
present options and ask, not assume:

1. **Backend prioritization for Phase B matrix proof.** Which backends
   matter most? Local-first (Ollama + Qwen-Coder) or enterprise-first
   (Azure OpenAI)? Maintainer's ranking drives Phase B order.

2. **Hardware budget for Phase C.** Try existing gaming laptop +
   Windows laptop first — free. If insufficient, the user has explicitly
   said evaluate $200 / $300 / $400 rig OR cloud-GPU rental. Don't spend
   without confirming.

3. **Capability-floor cutoff.** When a small local model (7–13B) fails
   the SDLC plan→TDD→self-review protocol, log it as a capability
   result and move on. Don't try to "fix" the wizard to support
   undersized models — that's not a port bug.

4. **Whether to mirror upstream-sync workflow.** The Codex sibling has
   `.github/workflows/upstream-sync.yml` that monitors the parent wizard
   for releases. Do we want the same here? Pros: stays in sync.
   Cons: another workflow to maintain. Defer to maintainer after Phase A
   proves the port works.

## Success criterion for v0.1.0 ship

A user can:
1. `npx opencode-sdlc-wizard init` in their project
2. Pick a backend (Ollama / Azure / Anthropic / etc.)
3. Have the wizard install hooks + skills into `.opencode/`
4. See SDLC BASELINE on next OpenCode session start
5. Get the TDD reminder when editing source files

If those 5 things work end-to-end on at least Anthropic + one OSS backend,
v0.1.0 ships. Backend matrix completeness is Phase B's problem.

## Anti-goals (things NOT to do in Phase A)

- **Don't build cross-backend benchmark scoring.** That's Phase B (#9).
- **Don't try to make the wizard "just work on every LLM."** The
  capability-floor note above explicitly says small models will fail and
  that's expected.
- **Don't spend on hardware or API credits without authorization.** Phase
  A is bounded zero-spend (Max subscription + free local).
- **Don't fork the Claude Code skill content.** Skills port verbatim
  per ROADMAP #91 — if there's a real divergence, propose it as an
  upstream change to claude-sdlc-wizard first, then re-sync.
- **Don't ship without cross-model review.** The parent repo's standard
  is Codex CERTIFIED before tag — same applies here.

## References (URLs)

- Parent wizard (canonical reference): https://github.com/BaseInfinity/claude-sdlc-wizard
- Closest sibling port (concrete adaptation example): https://github.com/BaseInfinity/codex-sdlc-wizard
- Games sibling (different domain, similar pattern): https://github.com/BaseInfinity/claude-gdlc-wizard
- XDLC umbrella: https://github.com/BaseInfinity/xdlc
- OpenCode upstream: https://github.com/sst/opencode
- Anthropic post-mortem driving cost concerns: https://www.anthropic.com/engineering/april-23-postmortem
- npm parent: https://www.npmjs.com/package/agentic-sdlc-wizard
- npm Codex sibling: https://www.npmjs.com/package/codex-sdlc-wizard

## Bootstrap session log (this session, 2026-05-03)

- Created repo `BaseInfinity/opencode-sdlc-wizard` (public, MIT)
- Wrote this `HANDOFF.md` (the thing you're reading)
- Wrote minimal `README.md`, `CLAUDE.md`, `LICENSE`, `.gitignore`,
  `package.json` scaffold

## Phase A implementation log (same session, extended 2026-05-03)

After bootstrap, the user authorized continuing into implementation
("take ur time"). Phase A was implemented end-to-end in the same
session. Cross-model review (Codex xhigh) caught 6 real findings; all
fixed. Final state pushed to main on `BaseInfinity/opencode-sdlc-wizard`.
**Status: Phase A code-complete, Codex round 1 fixes applied, pending
Codex round 2 recheck + tag/publish in a follow-up session.**

### What's on main right now (commit `3d4585f` and earlier)

```
opencode-sdlc-wizard/
├── AGENTS.md                              # primary instruction file
├── CHANGELOG.md                           # v0.1.0 release notes
├── CLAUDE.md                              # project notes for any CC session
├── HANDOFF.md                             # this file
├── LICENSE                                # MIT
├── README.md                              # public pitch + install + tests + limits
├── install.sh                             # non-destructive bash installer
├── package.json                           # v0.1.0
├── .opencode/
│   ├── plugins/sdlc-wizard.js             # JS plugin shim (the OpenCode adapter)
│   └── hooks/                             # 5 portable bash hooks + helper
│       ├── _find-sdlc-root.sh
│       ├── sdlc-prompt-check.sh
│       ├── tdd-pretool-check.sh
│       ├── instructions-loaded-check.sh
│       ├── model-effort-check.sh
│       └── precompact-seam-check.sh
├── hooks/                                 # mirror of .opencode/hooks/ (dev mode)
├── skills/                                # 4 OpenCode-native skills
│   ├── sdlc/SKILL.md                      # full workflow (verbatim from parent)
│   ├── setup-wizard/SKILL.md              # OpenCode-tailored, no Claude refs
│   ├── update-wizard/SKILL.md             # OpenCode-tailored, no Claude refs
│   └── feedback/SKILL.md                  # OpenCode-tailored, no Claude refs
├── tests/                                 # 80 tests, all green
│   ├── test-bundle-integrity.sh           # 57 tests
│   ├── test-plugin-shim.sh                # 11 tests
│   └── test-install.sh                    # 12 tests
└── .reviews/                              # cross-model review artifacts
    ├── handoff.json                       # Codex review handoff (round 1)
    ├── latest-review.md                   # Codex round-1 findings (4/10)
    ├── preflight-v0.1.0.md                # what we self-checked first
    └── response.json                      # round-2 responses (FIXED list)
```

### Codex round-1 findings (all FIXED)

The bootstrap session ran `codex exec` with xhigh effort against a live
OpenCode docs fetch + cross-references with parent + Codex sibling +
~/xdlc. Codex returned **4/10 NOT CERTIFIED** with these findings:

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| 1 | **P0** | `session.created` registered as direct handler key but OpenCode dispatches via generic `event` channel — would silently never fire | FIXED — generic `event` handler with `event.type` discriminator |
| 2 | **P0** | `tool.execute.before` destructured `{ tool, args }` but OpenCode passes `(input, output)` with lowercase tool ids — TDD nudge would never fire | FIXED — correct signature, lowercase ids, `output.args` extraction, apply_patch path-extraction fallback |
| 3 | P1 | Skill dir name (`setup`) didn't match frontmatter (`setup-wizard`) — OpenCode discovery rule violation | FIXED — dirs renamed to match frontmatter; AGENTS.md + install.sh updated; regression test added |
| 4 | P1 | Helper skills still Claude-only (CLAUDE_CODE_SDLC_WIZARD.md refs, .claude/settings.json paths, agentic-sdlc-wizard CLI invocations) | FIXED — setup-wizard / update-wizard / feedback rewritten OpenCode-native; stale-reference test added; sdlc skill kept verbatim (workflow not infra) |
| 5 | P2 | install.sh rewrote `.wizard-stamp` every run (not idempotent on the stamp file) | FIXED — gated stamp write on INSTALLED+UPDATED > 0; idempotency test added |
| 6 | P2 | README still labeled "bootstrap stage" after Phase A code shipped | FIXED — replaced banner; added Install / Tests / Known limitations sections |

Round-2 Codex recheck has NOT yet been run — that's the first thing the
follow-up session should do (see "Pickup steps" below).

### What the follow-up session needs to do

These are the concrete next steps in execution order. **Don't skip
the Codex round-2 recheck — it's the standing standard before any
sibling tags v0.1.0.**

1. **Run Codex round-2 recheck.** From the repo root:
   ```bash
   codex exec \
     -c 'model_reasoning_effort="xhigh"' \
     -s danger-full-access \
     -o .reviews/latest-review.md \
     "TARGETED RECHECK — not a full re-review. Read .reviews/handoff.json
      and .reviews/response.json. For each round-1 finding: FIXED → verify
      against original certify condition. DISPUTED → evaluate justification.
      Do NOT raise new findings unless P0. Re-verify all prior passes still
      hold. End with: score (1-10), CERTIFIED or NOT CERTIFIED."
   ```
   The response.json already enumerates which file:line pairs each
   finding was fixed in.

2. **If CERTIFIED (score ≥8):** tag v0.1.0 and publish:
   - Bump `package.json` version if needed (currently 0.1.0)
   - `git tag v0.1.0 && git push origin v0.1.0`
   - Set up npm publish flow (the parent wizard has a release.yml
     workflow — copy it to .github/workflows/ here)
   - Open the npm publish ticket — first-time publish to npm requires
     the user's npm OTP

3. **If NOT CERTIFIED:** another fix round. Update response.json with
   the new actions. Cap at 3 rounds total (per parent wizard policy).

4. **After v0.1.0 ships:** mirror updates back to siblings:
   - File issue in `BaseInfinity/claude-sdlc-wizard` to add OpenCode as
     row 4 in the README ecosystem table (currently 3 siblings;
     opencode-sdlc-wizard becomes 4th)
   - File issue in `BaseInfinity/codex-sdlc-wizard` for the same
     ecosystem table update
   - File issue in `BaseInfinity/claude-gdlc-wizard` for the same
   - Update parent's ROADMAP #9 to mark Phase A DONE; note v0.1.0
     URL + tag

### What was deliberately deferred (Phase B/C)

- **Backend matrix proof.** Run a paired E2E SDLC scenario (plan →
  TDD → self-review) against:
  - **Local tier:** Ollama + Qwen-Coder or DeepSeek-Coder (16-24GB
    VRAM class)
  - **Enterprise tier:** Azure OpenAI tenant
  - **Hosted OSS tier:** Together or Groq
  - **Anthropic baseline:** Opus 4.7 max
  Score each against parent's `tests/e2e/run-tier2-evaluation.sh`
  rubric (10-point criteria, 5 trials, 95% CI). Document which
  backends hold SDLC compliance and which degrade. Capability-floor
  note still applies: small models (7-13B) will fail and that's a
  result not a bug.

- **Hardware scout for local tier.** Test gaming laptop +
  Windows laptop first (zero spend). If insufficient, evaluate
  $200/$300/$400 rig OR cloud-GPU rental. Don't spend without
  maintainer authorization.

- **Upstream-sync workflow.** The Codex sibling has
  `.github/workflows/upstream-sync.yml` that monitors the parent
  wizard's releases and proposes parity updates. We don't have one yet.
  Add when the port stabilizes (post v0.1.0).

- **Native Node CLI.** `npx opencode-sdlc-wizard init` requires a
  `cli/bin/` entry. The parent wizard has 8 CLI files distributed via
  npm `bin`. Phase A ships bash-only install for simplicity; native
  CLI is a follow-up.

- **opencode.json plugin auto-load verification.** OpenCode plugins at
  `.opencode/plugins/` are documented as auto-loaded, but we have NOT
  end-to-end tested this against a live OpenCode install. The plugin
  passes static checks (parses, exports correct shape, uses right
  event names + signatures), but next session should run the wizard
  against a real OpenCode process and confirm hooks actually fire.

### Open questions for the maintainer (not for the next session to guess)

1. **Backend prioritization for Phase B.** Which matters most: local
   privacy (Ollama), enterprise compliance (Azure), or hosted OSS cost
   (Together/Groq)? The matrix has 4 cells but order them by user
   demand.

2. **Hardware budget.** Existing laptops first. Authorize spend only
   if those don't meet the 16-24GB VRAM bar for Qwen-Coder /
   DeepSeek-Coder.

3. **Upstream-sync cadence.** Daily/weekly/manual? The parent's
   weekly cron has been migrated to manual on-Max in #231; we may
   want to follow that pattern from day 1 here.

4. **npm publish account.** The wizard's npm scope is
   `BaseInfinity` — is `opencode-sdlc-wizard` going to publish under
   the same scope? If yes, no new account needed. The publish flow
   mirrors `release.yml` from the parent.

End of Phase A handoff. The actual implementation is on main; this
section is just the bridge to whoever takes Phase B.

## v0.2.0 addendum (2026-05-04) — backend picker

Phase A v0.1.0 deliberately deferred backend selection (`opencode.json` was
left alone by the installer). v0.2.0 closes that gap because the multi-
backend pitch in the README without an actual picker would be a documentation
lie. The differentiator that justifies this sibling vs `agentic-sdlc-wizard`
and `codex-sdlc-wizard` is **privacy-first portability**, and a footnote in
the README is not portability.

**What ships in v0.2.0:**

- `scripts/detect-backends.sh` — env probe + PATH probe → JSON with four
  tiers + a `recommendation` string. Privacy-first cascade. No network.
- `scripts/configure-backend.sh` — `--tier --provider --model` flags;
  writes/merges `opencode.json` non-destructively, refuses to clobber
  existing pins without `--force`, supports `--print-only` dry runs,
  idempotent.
- `PRIVACY.md` — four-tier model, Ollama walkthrough, verification.
- 15 new tests in `tests/test-backend-picker.sh`.

**Tier coverage decisions:**

- Local providers (Ollama / LM Studio / llama.cpp / vLLM) use OpenCode's
  `@ai-sdk/openai-compatible` provider with each runtime's documented
  localhost port. Confirmed against opencode.ai/docs/providers as of
  2026-05-04.
- API keys go through `{env:VAR}` substitution per OpenCode's documented
  config format. No secrets in `opencode.json`.
- Aliases accepted: `enterprise/azure` → `azure_openai`, `enterprise/bedrock`
  → `aws_bedrock`. The detector emits the canonical names; the configurator
  accepts both.

**Live E2E validation done (2026-05-04, opencode-ai@1.14.33).**
The "deferred unverified critical path" from v0.1.0 was run end-to-end
against a real OpenCode process. Findings + fixes:

- ✅ Plugin auto-loads from `.opencode/plugins/` (verified via
  `opencode debug config`).
- ✅ All 4 skills discovered (verified via `opencode debug skill`).
- ⚠️ **Session-start race fixed.** `session.created` publishes before
  async plugin factories resolve; v0.1.0 strict discriminator never
  fired. v0.2.0 uses first-`session.*` + dedupe to subscribe in the
  window we actually have.
- ⚠️ **Async shell paths hang.** Both `node:child_process.execFile` and
  Bun's `$` API never resolved when running bash hooks under OpenCode
  1.14.33. v0.2.0 uses `Bun.spawnSync` (synchronous) which completes
  deterministically.
- ✅ SDLC Wizard banner reaches OpenCode stderr live after the two fixes.

**Still deferred (Phase B / Phase C as before):**

- Backend matrix proof — score plan→TDD→self-review compliance across
  backends. Capability-floor note still applies.
- Hardware scout — gaming/Windows laptop first, $200–400 rig only with
  authorization.
- Native `npx` CLI — Phase A bash installer + the new scripts cover the
  workflow; native CLI is a follow-up.
- `tool.execute.before` and `experimental.session.compacting` E2E paths
  not yet exercised live (would require triggering tool calls / a
  compact under OpenCode). Static checks pass; runtime verification is
  a follow-up.

**Codex round-2 recheck:** v0.2.0 expands scope, so the round-2 review
should re-verify the 6 round-1 fixes AND audit the picker. Run from repo
root with `xhigh` effort, output to `.reviews/latest-review.md`. Then tag
v0.2.0 (not v0.1.0 — the picker is a meaningful new feature).

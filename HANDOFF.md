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

## Research checklist — verify these BEFORE porting

The bootstrap session (me) hasn't verified OpenCode's exact hook system. The
next session must confirm before writing port code:

- [ ] **What is OpenCode's hook event surface?** Read
      [sst/opencode docs](https://github.com/sst/opencode). Does it have
      analogues to Claude Code's `UserPromptSubmit`, `PreToolUse`,
      `PostToolUse`, `SessionStart`, `PreCompact`, `InstructionsLoaded`?
      What's the JSON schema for hook input/output? Where do hook scripts
      live (`.opencode/hooks/`?)?
- [ ] **What's the OpenCode equivalent of `.claude/settings.json`?** Probably
      `.opencode/settings.json` or `.opencode/config.toml` — verify and adapt
      `cli/templates/settings.json` from claude-sdlc-wizard accordingly.
- [ ] **Does OpenCode have a slash-command system equivalent to Claude
      Code's skills?** If yes, are skills discoverable via the same
      `SKILL.md` frontmatter convention? If no, document the gap and
      decide on a workaround (probably: ship as docs, invoke manually).
- [ ] **Does OpenCode persist conversation/session state in a way our
      `precompact-seam-check.sh` can hook into?** The hook gates manual
      compact when `.reviews/handoff.json` is in PENDING_RECHECK — does
      OpenCode have a compact event at all? If not, this hook may be a
      no-op for OpenCode and that's fine.
- [ ] **Backend selection mechanism.** How does a user tell OpenCode
      "use Ollama" vs "use Azure"? Setup wizard needs to detect or prompt
      for this and write the right config.
- [ ] **`AGENTS.md` vs `CLAUDE.md`.** Codex uses `AGENTS.md` because it's
      the standard agent-instruction file (works across many AI tools). Does
      OpenCode honor `AGENTS.md`? Pick whichever it natively reads.

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
- **Did not** create `hooks/`, `skills/`, `cli/`, `install.sh` — those
  belong to the implementation session
- **Did not** verify OpenCode's hook system — research checklist above
  is the explicit "first thing to do"
- Did not yet add OpenCode to the parent repo's README ecosystem table
  — defer until v0.1.0 ships, then update all 3 siblings + parent

End of handoff. Good luck — the Codex port is your friend.

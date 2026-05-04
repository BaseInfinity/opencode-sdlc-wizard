# OpenCode SDLC Wizard

> **Status: v0.1.0 (Phase A complete) — 2026-05-03.** Hooks, skills,
> AGENTS.md, and `install.sh` ship. Phase B (backend matrix proof) and
> Phase C (hardware scout) deferred to follow-up releases. See
> [`HANDOFF.md`](HANDOFF.md) for architecture decisions and
> [`CHANGELOG.md`](CHANGELOG.md) for release notes.

SDLC enforcement for [`sst/opencode`](https://github.com/sst/opencode) — the
privacy-first, any-backend agent CLI. This wizard ports the same plan → TDD
→ self-review enforcement pattern from the Claude / Codex siblings into the
OpenCode runtime, so users can get SDLC discipline against **whatever model
backend their privacy / compliance constraints allow** — not just Anthropic.

Supported backends OpenCode already speaks (and we'll inherit):
- **Local:** Ollama, LM Studio, llama.cpp, vLLM
- **Enterprise:** Azure OpenAI, AWS Bedrock, internal AI gateways
- **Hosted OSS:** Together, Groq, OpenRouter
- **Standard:** OpenAI, Anthropic

## XDLC Ecosystem (Sibling Projects)

This wizard is one of four sibling projects. Same enforcement philosophy,
different agent / domain:

| Package | Agent / Domain | What It Does |
|---------|----------------|--------------|
| [`agentic-sdlc-wizard`](https://www.npmjs.com/package/agentic-sdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-sdlc-wizard)) | Claude Code / SDLC | Plan → TDD → self-review for code, with hooks + skills + CI scoring |
| [`codex-sdlc-wizard`](https://www.npmjs.com/package/codex-sdlc-wizard) ([repo](https://github.com/BaseInfinity/codex-sdlc-wizard)) | OpenAI Codex / SDLC | Same SDLC enforcement, ported to Codex CLI (writes `.codex/` + `AGENTS.md`) |
| [`claude-gdlc-wizard`](https://www.npmjs.com/package/claude-gdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-gdlc-wizard)) | Claude Code / GDLC | Game Development Life Cycle — persona-driven playtest cycles, triangulated findings, ratchet-only-tightens |
| **`opencode-sdlc-wizard` (this repo)** | **OpenCode / SDLC** | **Same SDLC enforcement, ported to OpenCode (writes `.opencode/`). Privacy-first, any-backend.** |

All four are part of the broader [XDLC ecosystem](https://github.com/BaseInfinity/xdlc) — generalized lifecycle enforcement across agents and domains.

## Roadmap

Tracked as **ROADMAP #9** in the parent repo:
[`BaseInfinity/claude-sdlc-wizard/ROADMAP.md`](https://github.com/BaseInfinity/claude-sdlc-wizard/blob/main/ROADMAP.md).

Three phases:
- **Phase A (current target):** port hooks + skills + install.sh from
  Claude / Codex pattern. Ship v0.1.0.
- **Phase B:** backend matrix proof — run E2E SDLC scenario across local
  (Ollama + Qwen-Coder), enterprise (Azure OpenAI), hosted OSS
  (Together/Groq), and Anthropic baselines. Document which backends hold
  SDLC compliance.
- **Phase C:** hardware scout for the local-tier compute requirement
  (gaming laptop / Windows laptop / $200–400 rig / cloud GPU rental).

## Capability floor

"Just works on every LLM" is the dream but not the spec. Small local models
(7–13B) are expected to fail the full plan → TDD → self-review protocol —
instruction-following, long-context reasoning, and tool-use are all
load-bearing. The 30B+ code-tuned class (Qwen-Coder, DeepSeek-Coder) is
the likely local sweet spot. **A failed run on an undersized model is a
capability result, not a port bug.**

## Install

From a target repo's root:

```bash
git clone https://github.com/BaseInfinity/opencode-sdlc-wizard /tmp/opencode-sdlc-wizard
bash /tmp/opencode-sdlc-wizard/install.sh
```

This non-destructively merges the wizard into your `.opencode/`:

- `.opencode/plugins/sdlc-wizard.js` (the OpenCode plugin shim)
- `.opencode/hooks/*.sh` (5 portable bash hooks)
- `.opencode/skills/{sdlc,setup-wizard,update-wizard,feedback}/SKILL.md`
- `AGENTS.md` at repo root (OpenCode's primary instruction file)

Existing customizations are preserved. Re-run with `--force` to overwrite.

A native `npx opencode-sdlc-wizard init` CLI is on the roadmap; for now
the bash installer is the supported path.

## Tests

```bash
bash tests/test-bundle-integrity.sh   # 50+ tests, bundle correctness
bash tests/test-plugin-shim.sh        # plugin ESM + bash hook validity
bash tests/test-install.sh            # installer non-destructive behavior
```

Or `npm test` runs all three.

## Known limitations

- **No `UserPromptSubmit` analog in OpenCode.** SDLC BASELINE moves to
  AGENTS.md (loaded once per session) instead of repeating per prompt.
- **Phase A only.** Backend matrix proof (Phase B) and hardware scout
  (Phase C) deferred. The wizard installs and runs against any OpenCode
  backend; we just haven't yet measured SDLC-compliance scores across
  backends statistically.
- **No upstream-sync workflow yet.** Updates from the parent
  `claude-sdlc-wizard` are manual. Future releases will mirror the
  Codex sibling's `.github/workflows/upstream-sync.yml` pattern.

## License

[MIT](LICENSE)

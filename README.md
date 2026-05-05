# OpenCode SDLC Wizard

> **Status: v0.6.0 (full template set + check subcommand + drift
> detection + OSS-tier reviewer + backend picker) — 2026-05-05.**
> Install with `npx opencode-sdlc-wizard init`, check upstream with
> `npx opencode-sdlc-wizard check`. Full SDLC loop is any-backend on
> both coder AND reviewer (zero Anthropic+OpenAI lock-in possible);
> setup-wizard ships SDLC.md + ARCHITECTURE.md + 4 domain-specific
> TESTING.md templates so consumers don't reinvent.
> Phase B (backend matrix proof) and Phase C (hardware scout) deferred to
> follow-up releases. See [`HANDOFF.md`](HANDOFF.md) for architecture
> decisions, [`PRIVACY.md`](PRIVACY.md) for the tier model, and
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

From a target repo's root, the easiest path:

```bash
npx opencode-sdlc-wizard init
```

That's it. Equivalent to the longer manual form:

```bash
git clone https://github.com/BaseInfinity/opencode-sdlc-wizard /tmp/opencode-sdlc-wizard
bash /tmp/opencode-sdlc-wizard/install.sh
```

Both paths are supported. `npx` is preferred for first-time installs;
`git clone + install.sh` is preferred when you want to inspect the bundle
before merging it. Re-run with `--force` to overwrite customizations,
`--dry-run` to preview without writing.

This non-destructively merges the wizard into your `.opencode/`:

- `.opencode/plugins/sdlc-wizard.js` (the OpenCode plugin shim)
- `.opencode/hooks/*.sh` (5 portable bash hooks)
- `.opencode/scripts/{detect,configure}-backend.sh` (privacy-first picker)
- `.opencode/skills/{sdlc,setup-wizard,update-wizard,feedback}/SKILL.md`
- `AGENTS.md` and `PRIVACY.md` at repo root

Existing customizations are preserved. Re-run with `--force` to overwrite.

Native `npx opencode-sdlc-wizard init` shipped in v0.3.0. The bash
installer remains the inspection/scripting path.

## Pick a backend (privacy-first)

```bash
# See what's reachable from this machine
bash .opencode/scripts/detect-backends.sh

# Configure the highest-privacy tier you can use
bash .opencode/scripts/configure-backend.sh \
     --tier private_local --provider ollama \
     --model qwen2.5-coder:32b
```

Four tiers, ordered by where your prompts travel:

| Tier | Travels to | Examples |
|------|------------|----------|
| `private_local` | Stays on your machine | Ollama, LM Studio, llama.cpp, vLLM |
| `enterprise` | Your tenant | Azure OpenAI, AWS Bedrock |
| `hosted_oss` | Third-party host | Together, Groq, OpenRouter |
| `proprietary` | Vendor (Anthropic/OpenAI) | Claude, GPT |

Detector probes PATH + env vars only — no network calls. Configurator merges
non-destructively into `opencode.json` and refuses to clobber an existing
`model` pin without `--force`. See [`PRIVACY.md`](PRIVACY.md) for the
Ollama walkthrough and verification checklist.

## Tests

```bash
bash tests/test-bundle-integrity.sh   # bundle correctness
bash tests/test-plugin-shim.sh        # plugin ESM + bash hook validity
bash tests/test-install.sh            # installer non-destructive behavior
bash tests/test-backend-picker.sh     # detect/configure-backend behavior
bash tests/test-cli.sh                # npx CLI wrapper
```

Or `npm test` runs all five.

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

# SDLC Baseline (OpenCode)

This file is loaded automatically at the start of every OpenCode session
in this project. It carries the same SDLC enforcement rules that the
`sdlc-wizard` ecosystem applies across Claude Code, Codex, and OpenCode.

## SDLC Baseline (every session)

1. **Plan before coding** — state confidence level (HIGH / MEDIUM / LOW)
2. **TDD: Write failing test FIRST**, then implement
3. **ALL tests must pass before commit** — no exceptions
4. **Self-review before presenting** — read back the diff, look for
   obvious issues
5. **LOW confidence → ASK USER before proceeding**
6. **Failed twice → STOP and ASK USER** — don't spin

## Agent Skills Available

Skills are auto-discovered from `.opencode/skills/` (and Claude-compatible
`.claude/skills/`). The four canonical skills:

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `sdlc` | `skill({ name: "sdlc" })` | Full SDLC workflow guidance |
| `setup-wizard` | `skill({ name: "setup-wizard" })` | Confidence-driven project setup |
| `update-wizard` | `skill({ name: "update-wizard" })` | Smart update with drift detection |
| `feedback` | `skill({ name: "feedback" })` | Privacy-first community feedback |

Read each skill's `SKILL.md` for full guidance.

## Workflow Phases

1. **Plan** (research + outline) → present approach + confidence
2. **Transition** (update docs) — feature docs current before commit
3. **Implementation** — TDD RED → GREEN → PASS
4. **Self-review** — read modified files, check for issues
5. **Cross-model review** (high-stakes changes) — see SDLC skill

## Hook Behavior (this project)

OpenCode does not have a Claude-style declarative hook config; the
`.opencode/plugins/sdlc-wizard.js` plugin subscribes to events and
shells out to bash hooks at `.opencode/hooks/`:

| Event | Hook | Purpose |
|-------|------|---------|
| `session.created` | `instructions-loaded-check.sh` + `model-effort-check.sh` | Validate SDLC files exist; nudge model/effort upgrades |
| `tool.execute.before` (Write/Edit on source) | `tdd-pretool-check.sh` | TDD reminder before source edits |
| `experimental.session.compacting` | `precompact-seam-check.sh` | Block compact mid-review or in-flight rebase/merge |

There is **no `UserPromptSubmit` analog** in OpenCode, so the per-prompt
SDLC BASELINE reminder from the Claude/Codex siblings is replaced by
this AGENTS.md content (loaded once per session). If you need a stronger
nudge cadence, invoke `skill({ name: "sdlc" })` explicitly.

## Recommended Backend Configuration

OpenCode supports many backends via `opencode.json`'s `model` field. This
wizard ships a **privacy-first picker** that defaults to the strongest
data-locality guarantee available on the machine.

Pick a backend in two steps:

```bash
# What's reachable on this machine?
bash .opencode/scripts/detect-backends.sh

# Or bias toward free providers (Cerebras / Groq / NVIDIA NIM / Google AI Studio quotas)
bash .opencode/scripts/detect-backends.sh --free-tier-first

# Configure the highest-privacy tier you can use
bash .opencode/scripts/configure-backend.sh \
     --tier private_local --provider ollama \
     --model qwen3-coder:30b
```

Tiers (privacy-first ordering):

| Tier | Where prompts travel | Examples |
|------|----------------------|----------|
| `private_local` | Stays on your machine | Ollama, LM Studio, llama.cpp, vLLM, MLX (Apple Silicon) |
| `enterprise` | Stays in your tenant | Azure OpenAI, AWS Bedrock |
| `hosted_oss` | Open weights, third-party host | Together, Groq, OpenRouter, Cerebras, DeepSeek direct, NVIDIA NIM (`nvidia_nim`) |
| `proprietary` | Vendor-bound | Anthropic, OpenAI, Google AI Studio (`google_aistudio` — Gemini), Z.AI (`zai` — GLM Coding Plan, post-Anthropic-OAuth-ban migration target) |
| `managed` | OpenCode-routed PAYG | OpenCode Zen (`opencode` — 40+ models incl. free tier; official new-user entry point) |
| `subscription` | Pre-paid sub via OAuth | GitHub Copilot Pro+ (`github-copilot`), ChatGPT Plus/Pro (`openai-codex` / `chatgpt`), SuperGrok (`grok` / `xai`) — all via `opencode /connect` |

See [`docs/cost-ladder.md`](docs/cost-ladder.md) for $0/$20/$200 monthly
budget paths and a per-job picker (routine fix vs long-context refactor
vs CI gate vs security audit).

The SDLC enforcement works on any backend that hits the **capability floor**
(30B+ code-tuned models — Qwen-Coder, DeepSeek-Coder, Sonnet, Opus, GPT-5.x).
Smaller models (7–13B) typically fail the full plan→TDD→self-review
protocol; that's a capability result, not a wizard bug.

See [`PRIVACY.md`](PRIVACY.md) for full tier walkthroughs, the Ollama
private-path setup, and how to verify no prompts are leaving the machine.

## Sibling Family

This wizard is one of four published siblings:

| Package | Agent | Repo |
|---------|-------|------|
| `agentic-sdlc-wizard` | Claude Code | https://github.com/BaseInfinity/claude-sdlc-wizard |
| `codex-sdlc-wizard` | Codex CLI | https://github.com/BaseInfinity/codex-sdlc-wizard |
| `claude-gdlc-wizard` | Claude Code (games) | https://github.com/BaseInfinity/claude-gdlc-wizard |
| `opencode-sdlc-wizard` (this) | OpenCode | https://github.com/BaseInfinity/opencode-sdlc-wizard |

Part of the [XDLC ecosystem](https://github.com/BaseInfinity/xdlc).

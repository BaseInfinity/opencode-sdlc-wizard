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
| `setup` | `skill({ name: "setup" })` | Confidence-driven project setup |
| `update` | `skill({ name: "update" })` | Smart update with drift detection |
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

OpenCode supports many backends via `opencode.json`'s `model` field. The
SDLC enforcement works on any backend that hits the **capability floor**
(generally 30B+ code-tuned models — Qwen-Coder, DeepSeek-Coder, Sonnet,
Opus, GPT-5.x). Smaller models (7-13B) typically fail the full
plan→TDD→self-review protocol; that's a capability result, not a wizard
bug.

For privacy-sensitive work, route through:
- **Local:** Ollama with Qwen-Coder or DeepSeek-Coder (16-24GB VRAM)
- **Enterprise:** Azure OpenAI tenant with zero-retention policy
- **Hosted OSS:** Together / Groq / OpenRouter

For maximum capability, use Anthropic / OpenAI flagship models directly.

## Sibling Family

This wizard is one of four published siblings:

| Package | Agent | Repo |
|---------|-------|------|
| `agentic-sdlc-wizard` | Claude Code | https://github.com/BaseInfinity/claude-sdlc-wizard |
| `codex-sdlc-wizard` | Codex CLI | https://github.com/BaseInfinity/codex-sdlc-wizard |
| `claude-gdlc-wizard` | Claude Code (games) | https://github.com/BaseInfinity/claude-gdlc-wizard |
| `opencode-sdlc-wizard` (this) | OpenCode | https://github.com/BaseInfinity/opencode-sdlc-wizard |

Part of the [XDLC ecosystem](https://github.com/BaseInfinity/xdlc).

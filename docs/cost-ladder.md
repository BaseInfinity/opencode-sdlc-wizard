# Cost Ladder

Concrete tier choices for `opencode-sdlc-wizard` users — what the SDLC
loop actually costs at three monthly budgets, what trade-offs each
budget forces, and which models clear the SDLC capability floor in each
slot.

This is the document that complements the four privacy tiers in
`PRIVACY.md`. Privacy is "where does my data go?" Cost is "how much
am I paying for ceiling vs floor?" Most teams need to balance both.

## SDLC capability floor (the unmoving constraint)

Before picking a model, know the floor. The SDLC protocol (plan → TDD →
self-review → optional cross-model review) requires:

1. **Decent instruction-following** — multi-step tool calls without
   hallucinated arguments.
2. **Long-context reasoning** — tracking a plan across 20-50 turns.
3. **Tool-use reliability** — handling structured edits, bash output,
   schema validation.

| Class | Examples | Holds the protocol? |
|-------|----------|---------------------|
| 7B–13B | Mistral 7B, Llama 3.2 8B, Qwen-Coder-7B | **No.** Fails partway. |
| 14B–22B | Phi-4 14B, DeepSeek-Coder-V2-16B, Codestral 22B | **Borderline.** Routine fixes OK; complex refactors slip. |
| 30B–70B code-tuned | Qwen2.5-Coder-32B, Qwen3-Coder, Llama 3.3 70B | **Yes.** The local sweet spot. |
| 100B+ open-weight | DeepSeek-V3.1 (671B MoE), GPT-OSS 120B | **Yes.** Strongest OSS reasoning. |
| Frontier proprietary | Claude Opus, GPT-5.5 xhigh, Gemini 2.5 Pro | **Yes.** Ceiling. |

Below the 30B-code-tuned bar, the wizard installs and runs but the
protocol degrades. That's a capability outcome, not a port bug.

## $0/mo path — pure free tiers

For hobbyists, students, or anyone evaluating the wizard before
committing.

```bash
# Detect what's reachable, biased toward free providers
bash .opencode/scripts/detect-backends.sh --free-tier-first

# Pick the highest-leverage free option (verify the exact model ID
# against the provider's current catalog — see "Verifying current
# model IDs" below; these change faster than this doc ships)
bash .opencode/scripts/configure-backend.sh \
  --tier hosted_oss --provider cerebras \
  --model qwen-3-235b-a22b-instruct-2507
```

| Slot | Provider | Example model (verify before use) | Why | Cost |
|------|----------|-----------------------------------|-----|------|
| Coder | Cerebras free | `qwen-3-235b-a22b-instruct-2507` or `gpt-oss-120b` | Fastest inference (~2000 tok/s), generous daily quota | $0 |
| Coder (alt) | Groq free | `llama-3.3-70b-versatile` | Sub-second, free tier resets daily | $0 |
| Coder (alt) | Google AI Studio | `gemini-2.5-flash` (1M context) | Generous daily request quota — verify current limits | $0 |
| Coder (alt) | OpenRouter | `deepseek/deepseek-chat:free` | Aggregator routing, OSS models | $0 (rate-limited) |
| Reviewer | NVIDIA NIM | `deepseek-ai/deepseek-r1` | Reasoning model, free credits at build.nvidia.com | $0 |
| Reviewer (alt) | OpenRouter | `qwen/qwen-3-coder:free` | Code-tuned, free routing | $0 (rate-limited) |

> **Verifying current model IDs.** Provider catalogs change monthly.
> Before pinning a model, sanity-check the ID against the provider's
> live docs — Cerebras: <https://inference-docs.cerebras.ai/models/overview>,
> Google AI Studio: <https://ai.google.dev/gemini-api/docs/models>,
> NVIDIA NIM: <https://build.nvidia.com>, Groq:
> <https://console.groq.com/docs/models>. The IDs in this table were
> calibrated 2026-05-05; codex round-1 review caught `llama-3.3-70b`
> as no longer in Cerebras's catalog and `gemini-2.0-flash` as
> deprecated (shutdown June 2026). If `configure-backend` writes a
> stale ID, `opencode run` will surface a clear `model not found`
> error — fixable in seconds, not a footgun.

**Real constraints at $0:**
- Daily quotas reset, but agentic loops burn fast — one complex task
  can exhaust Groq's daily cap.
- OpenRouter `:free` variants are aggressively throttled under load.
- Free tiers may log your prompts for training (read each provider's
  policy). Privileged-data work belongs in `private_local`, not free
  hosted.
- No SLA. Outages happen.

**What you give up vs paid:** ceiling on novel architecture decisions,
long-context refactors, and "this is gnarly, throw the strongest model
at it" moments. For routine fixes + TDD loops, the gap is small.

## $0/mo path — local-only (no egress)

Same budget, different trade-off: hardware capex instead of token spend.
For privileged-data work, NDA contracts, or anyone who wants zero
egress.

| Slot | Tool | Model | Hardware floor |
|------|------|-------|----------------|
| Coder | Ollama | `qwen3-coder:30b` | 24GB VRAM (RTX 4090, M-series 32GB+) |
| Coder | Ollama | `deepseek-coder-v2:16b` | 16GB VRAM (RTX 4070 Ti, M Pro 16GB) |
| Coder | LM Studio | `Qwen3-Coder-30B-Instruct` | Same as above |
| Coder | MLX (Apple Silicon) | `mlx-community/Qwen2.5-Coder-32B-Instruct-4bit` | 32GB unified memory; fastest on M-series |
| Reviewer | Ollama | `qwen3-coder:30b` (same instance) | Use sequentially |

```bash
# Local + privacy-first
bash .opencode/scripts/configure-backend.sh \
  --tier private_local --provider ollama \
  --model qwen3-coder:30b
```

**Constraints:**
- Hardware is the floor. <16GB VRAM = no serious local work for SDLC.
- Inference is slower than hosted (token/sec on a single consumer GPU
  vs Cerebras's wafer-scale farm).
- One model at a time means no parallel coder+reviewer (or you swap
  contexts).

## $20/mo path — one premium subscription, harvest free for the rest

Most professional engineers' sweet spot. One ceiling model where
ceiling matters, free for the rest.

| Slot | Provider | Model | Cost | Why |
|------|----------|-------|------|-----|
| Coder | Anthropic Claude (Pro) | `claude-sonnet-4.6` | $20/mo Pro sub or ~$3/M in via API | Best instruction-following + tool-use |
| Coder (alt) | OpenAI Plus | `gpt-5.5` | $20/mo Plus sub | Strong reasoning, especially with xhigh effort |
| Reviewer | Cerebras free / Groq free | `gpt-oss-120b` (Cerebras) or `llama-3.3-70b-versatile` (Groq) | $0 | Cheap second opinion |
| Reviewer (alt) | DeepSeek direct | `deepseek-chat` | ~$0.14/M in cache-miss (pennies/review) — verify current pricing | Strong OSS reasoning, cheapest hosted |
| Reviewer (high-stakes) | Codex via API | `gpt-5.5` xhigh | ~$1-3 per review at xhigh | When release-critical |

```bash
# v0.10.0: Mixed-Mode in one shot via `pick` — coder + reviewer split
# the work, OpenCode auto-routes review tasks via agent.review.model
npx opencode-sdlc-wizard pick \
  --tier proprietary --provider anthropic \
  --reviewer-tier hosted_oss --reviewer-provider cerebras

# Equivalent low-level invocation (what `pick` orchestrates under it):
bash .opencode/scripts/configure-backend.sh \
  --tier proprietary --provider anthropic --model claude-sonnet-4.6 \
  --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b
```

**The hybrid pattern that maximizes this budget:**
- Coder = ceiling (Claude / GPT-5.5) for new code
- Reviewer = cheap (DeepSeek direct or Cerebras free) for the
  "second pair of eyes" pass
- Saves ~80% of review tokens vs running Claude on both sides without
  losing rigor

v0.10.0 ships Mixed-Mode in `pick` and `configure-backend.sh` —
emits both provider blocks plus `agent.review.model` so OpenCode
routes review tasks to the reviewer without any wrapper script.

## $200/mo path — agentic-grade, multi-agent loops

For shops running CI gates on every PR, daily multi-hour agent loops,
or anyone whose time is more valuable than tokens.

| Slot | Provider | Model | Approx monthly | Why |
|------|----------|-------|----------------|-----|
| Coder | Anthropic | `claude-opus-4.7` | ~$100-150 | Highest ceiling, 1M context tier |
| Coder (alt) | OpenAI | `gpt-5.5` xhigh | ~$80-130 | Strongest reasoning at xhigh effort |
| Reviewer | Codex CLI (xhigh) | `gpt-5.5` | ~$30-50 | Cross-model review on every release |
| Reviewer (parallel) | DeepSeek direct | `deepseek-r1` | ~$10-20 | Cheap second-reviewer for triangulation |
| CI gate | Groq free / Cerebras free | `llama-3.3-70b-versatile` (Groq) or `gpt-oss-120b` (Cerebras) | $0 | Fast PR-review loops, free tier |

**The pattern that earns this budget:**
- Three reviewers: codex (xhigh), DeepSeek-R1, plus the originating
  coder's self-review. Triangulated findings catch what any single
  reviewer misses.
- CI gates on every PR using a free fast reviewer (Groq) — the
  expensive reviewers fire only on release branches.
- 1M-context tier on the coder for whole-monorepo refactors.

## Picking by job, not by tier

Forget the budget bracket for a sec — pick by what the job is.

| Job | Best tier | Best model | Notes |
|-----|-----------|-----------|-------|
| Routine fix / typo / small CSS | hosted_oss free | Cerebras `gpt-oss-120b` or `qwen-3-235b-a22b-instruct-2507` | Fast + free + clears the bar |
| TDD on new feature, mid-stakes | $20 path | Claude Sonnet 4.6 | Tool-use is its strength |
| Long-context refactor | $200 path | Opus 4.7 (1M context) | Floor is "fits in context" |
| Security audit / privileged code | private_local | Qwen2.5-Coder-32B local | Zero egress |
| CI gating on every PR | hosted_oss free | Groq `llama-3.3-70b-versatile` | Speed + cost dominate (Groq still ships Llama 3.3 70B; Cerebras dropped it) |
| Architecture decision (novel) | $200 path | Opus 4.7 + Codex xhigh review | Ceiling matters |
| Bulk doc / refactor sweeps | hosted_oss cheap-paid | DeepSeek-V3.1 direct | Cheap per token, decent quality |
| Air-gapped / compliance-locked | private_local | Whatever fits VRAM | Hardware floor matters more than ceiling |

## Where this wizard helps regardless of tier

The SDLC protocol (plan → TDD → self-review → optional cross-model
review) is **model-agnostic**. The hooks fire under any backend
OpenCode supports. The skills work with any model that clears the
capability floor.

That's the actual point: the wizard is not about a specific tier
winning. It's about the **discipline** holding regardless of what
model you're paying (or not paying) for.

## Updating this doc

This is a snapshot — pricing and free-tier generosity shift faster
than the wizard ships. If a number is stale by more than a few months
or a provider has changed their tier structure, open an issue. The
ratios (DeepSeek roughly an order of magnitude cheaper than Opus,
Cerebras roughly an order of magnitude faster than hosted
alternatives) tend to hold longer than the absolute prices.

**Specific calibration notes** for the prices/quotas in this doc:

- DeepSeek `deepseek-chat` ≈ `$0.14/M in` cache-miss (was `$0.27/M`
  in v0.8.0 — codex round-1 F4 caught the stale figure). Cache-hit
  pricing is meaningfully cheaper. Verify at
  <https://api-docs.deepseek.com/quick_start/pricing>.
- Gemini 2.0 Flash is deprecated with shutdown 2026-06-01 — use
  `gemini-2.5-flash` instead. Free quota is per-model and changes;
  some quotas apply only to grounded prompts. Verify at
  <https://ai.google.dev/gemini-api/docs/rate-limits>.
- Cerebras catalog rotates faster than other providers — `llama-3.3-70b`
  was in v0.8.0 of this doc, but as of 2026-05-05 the public production
  models are `llama3.1-8b`, `gpt-oss-120b`, `qwen-3-235b-a22b-instruct-2507`,
  and `zai-glm-4.7`. Verify at
  <https://inference-docs.cerebras.ai/models/overview>.
- Together initial credit and Groq daily quota change frequently —
  always recheck.

Last calibrated: 2026-05-05 (codex round-1 corrections applied for
v0.8.1).

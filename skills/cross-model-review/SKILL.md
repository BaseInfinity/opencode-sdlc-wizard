---
name: cross-model-review
description: Run a cross-model SDLC review through OpenCode using an OSS-tier model (DeepSeek-V3 / Qwen2.5-Coder / Llama 3.3) instead of Codex. Use when finalizing a release or any high-stakes change without depending on Anthropic+OpenAI for the review step.
---

# Cross-Model Review (OSS-tier reviewer)

## Purpose

Symmetric path to the Codex review flow but with no OpenAI dependency.
Coder can be any backend (Claude / OpenCode / Ollama / etc.); reviewer
can also be any backend. This skill runs the **review** step through
OpenCode with an OSS-tier model so the full SDLC loop has zero
Anthropic+OpenAI lock-in when needed.

Use it whenever you would have run:

```
codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access \
  -o .reviews/latest-review.md "<recheck-prompt>" </dev/null
```

…but want OSS instead. Or in air-gapped contexts where the reviewer must
also be local (Ollama Qwen2.5-Coder-32B against local code, no network).

## Reasoning policy

Default to `xhigh` reasoning when the underlying model supports it
(DeepSeek-V3 has reasoning modes; smaller Llama / Qwen variants are
single-pass). Match the cross-model-review effort level to the parent
SDLC step's effort: max effort coder → max effort reviewer.

## Scope guard

This skill **only** owns running the review and writing
`.reviews/latest-review.md`. It does NOT:
- modify code
- merge PRs
- open issues
- decide whether to ship (the user reads the review and decides)

## Workflow

### Step 1 — Prerequisites

Verify:
- `.reviews/handoff.json` exists (the review's "what to verify" doc)
- `.reviews/response.json` exists (the round-N "what we fixed" claims)
- `opencode` is on PATH (`which opencode` succeeds)
- An OSS provider is reachable: either local Ollama running on
  `:11434` with the chosen model pulled, or an API key set for a
  hosted-OSS provider (`TOGETHER_API_KEY` / `GROQ_API_KEY` /
  `OPENROUTER_API_KEY`)

If `.reviews/handoff.json` is missing, surface this to the user and
stop — the skill does not auto-generate a handoff. Direct them to the
`feedback` or `setup-wizard` skill if they're not sure how to create one.

### Step 1.5 — Validate review artifacts against the schema

Before sending the prompt to a reviewer, validate the handoff + response
JSON against the canonical schemas. A malformed handoff wastes reviewer
tokens and produces a confused review. Validation is fast (zero deps,
pure node).

```bash
bash .opencode/scripts/validate-review-artifact.sh \
  .reviews/handoff.json \
  .opencode/schemas/handoff.schema.json

bash .opencode/scripts/validate-review-artifact.sh \
  .reviews/response.json \
  .opencode/schemas/response.schema.json
```

Both must exit 0 before proceeding. If either fails, fix the artifact
(the validator prints jsonpath + reason for every error) and re-run.
The schemas codify the structure used across review rounds — they're
also what `ditto` v0.1.0 will consume to migrate review artifacts
between sibling repos.

### Step 2 — Pick a reviewer model

Recommend by tier (privacy-first ordering). Verify model IDs against
each provider's live catalog — see `docs/cost-ladder.md` for the
calibration links and current $0/$20/$200 budget paths.

| Tier | Provider | Model | Strengths |
|------|----------|-------|-----------|
| `private_local` | ollama | `qwen2.5-coder:32b` | Code-tuned, runs locally, zero egress |
| `private_local` | ollama | `deepseek-coder-v2:16b` | Smaller, faster locally |
| `private_local` | mlx | `mlx-community/Qwen2.5-Coder-32B-Instruct-4bit` | Apple Silicon native, fastest local on M-series |
| `hosted_oss` | cerebras | `gpt-oss-120b` or `qwen-3-235b-a22b-instruct-2507` | **Free tier**, ~2000 tok/s, generous daily quota |
| `hosted_oss` | deepseek | `deepseek-chat` | **Cheapest hosted reasoning** (~$0.14/M cache-miss), strongest OSS ceiling |
| `hosted_oss` | nvidia_nim | `deepseek-ai/deepseek-r1` | Free credits at build.nvidia.com, hosts most OSS models |
| `hosted_oss` | togetherai | `deepseek-ai/DeepSeek-V3.1` | Strong reasoning OSS, drop-in for DeepSeek direct |
| `hosted_oss` | groq | `llama-3.3-70b-versatile` | Fastest hosted (sub-second), free tier daily reset |
| `hosted_oss` | openrouter | `qwen/qwen-2.5-coder-32b-instruct` | OpenRouter's gateway routing |

**Default suggestion** depends on the budget bucket — see
`docs/cost-ladder.md` for $0 / $20 / $200 monthly paths and the per-job
picker. Common picks: `cerebras/gpt-oss-120b` (free + fastest),
`deepseek/deepseek-chat` (cheapest paid, strongest reasoning), or
local `ollama/qwen2.5-coder:32b` when egress is the constraint.

### Step 3 — Run the review

Invoke the bundled wrapper script (installed at
`.opencode/scripts/cross-model-review.sh` in target repos):

```bash
# Free tier path — Cerebras gpt-oss-120b (default suggestion when free
# providers are reachable; fastest review per dollar = $0)
bash .opencode/scripts/cross-model-review.sh \
  --reviewer-provider cerebras \
  --reviewer-model gpt-oss-120b \
  --reviewer-tier hosted_oss

# Cheapest paid path — DeepSeek direct (strongest hosted reasoning, ~$0.14/M)
bash .opencode/scripts/cross-model-review.sh \
  --reviewer-provider deepseek \
  --reviewer-model deepseek-chat \
  --reviewer-tier hosted_oss
```

The script:
- Validates inputs (handoff present, opencode on PATH)
- Composes the recheck prompt from `handoff.json` + `response.json`
- Invokes `opencode run --model <provider>/<model>` with the prompt
- Captures stdout to `.reviews/latest-review.md`
- Returns opencode's exit code

Use `--print-prompt` first if you want to inspect/customize the
prompt before consuming OSS tokens:

```bash
bash .opencode/scripts/cross-model-review.sh \
  --reviewer-provider cerebras --reviewer-model gpt-oss-120b --print-prompt
```

### Step 4 — Read the verdict

The reviewer's output is in `.reviews/latest-review.md` and ends with:

```
Score: <n>/10
Certification: CERTIFIED  (or NOT CERTIFIED)
```

Plus a per-finding table.

If `CERTIFIED` (score ≥ 8): proceed to ship.
If `NOT CERTIFIED`: read the table, address findings, update
`response.json`, re-run this skill (round-N+1).

Cap at 3 review rounds total per release (per parent wizard policy).
If still NOT CERTIFIED after round 3, the change needs a larger rethink
than another fix-loop will solve.

## When to use this skill vs the codex flow

| Situation | Reviewer |
|-----------|----------|
| You have ChatGPT subscription + want max-capability review | codex (gpt-5.5 xhigh) |
| You don't have OpenAI access OR want to avoid the dependency | this skill (DeepSeek-V3) |
| Air-gapped / privileged-data context | this skill with local Ollama |
| Cost-sensitive (frequent reviews) | this skill (Together / Groq pennies vs codex tokens) |
| Speed-sensitive (CI gating on review) | this skill with Groq (sub-second) |

The two flows produce structurally identical artifacts in
`.reviews/latest-review.md`, so downstream consumers (e.g.,
release.yml, CI tooling) don't care which reviewer was used.

## What this skill deliberately does NOT do

- **Pick the reviewer model for you.** The user provides
  `--reviewer-provider` + `--reviewer-model`. Recommendations above are
  defaults, not auto-selected.
- **Auto-loop on NOT CERTIFIED.** Each round is a deliberate human
  decision, not a retry-until-pass.
- **Replace codex.** You can use both; they're complementary cross-model
  reviewers. Running both gives you a two-reviewer triangulation if a
  release is high-stakes.
- **Touch the code being reviewed.** Read-only.

## Privacy guarantees

When `--reviewer-provider ollama`: zero network egress. Everything stays
on your machine — coder + reviewer + code.

When `--reviewer-provider togetherai/groq/openrouter`: review prompt
(your handoff.json + response.json content) goes to that provider's API.
The provider's logging policy applies. If your handoff/response contain
sensitive code paths, prefer `private_local` with Ollama.

When `--reviewer-provider anthropic/openai`: this skill works but defeats
the purpose — at that point use the codex flow directly.

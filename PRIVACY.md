# Privacy Tiers — Choosing a Backend

OpenCode SDLC Wizard supports six backend tiers. Tiers are ordered by where
your prompts and code can travel. The wizard's recommendation defaults to the
strongest privacy guarantee available, not the strongest model ceiling.

| Tier | Where prompts travel | Best for |
|------|----------------------|----------|
| **`private_local`** | Stays on your machine. No outbound traffic. | Privileged data, attorney-client work, air-gapped environments, source you cannot send to a third party |
| **`enterprise`** | Stays in your tenant. Vendor processes under contract; zero-retention configurable. | Regulated companies with an Azure/Bedrock/internal-gateway agreement that meets compliance |
| **`hosted_oss`** | Sent to a third-party host of open-weight models. Logging policy is the host's. | Cost-sensitive work where the model weights are open but you'd rather pay-per-token than self-host |
| **`managed`** | Sent to OpenCode's hosted routing service (OpenCode Zen). PAYG, vendor-managed model selection. Free tier available. | Lowest-friction "just give me a working setup" option; new-user entry per official OpenCode docs |
| **`proprietary`** | Sent to Anthropic / OpenAI / Google / Z.AI. Vendor's standard ToS applies. | Maximum capability ceiling when privacy isn't the binding constraint |
| **`subscription`** | Sent via vendor-managed OAuth (GitHub Copilot Pro+). Auth lives in OpenCode's user state, not `opencode.json`. | Flat-fee bridge to Opus 4.7 + GPT-5.3-Codex post-Anthropic-OAuth-ban; $39/mo all-you-can-eat |

## How to pick

```bash
# 1. See what's already available on this machine
bash .opencode/scripts/detect-backends.sh

# 2. Configure the highest-privacy option you can use
bash .opencode/scripts/configure-backend.sh \
     --tier private_local --provider ollama \
     --model qwen3-coder:30b
```

The detector probes PATH (Ollama, LM Studio, llama.cpp, vLLM) and env vars
(`AZURE_RESOURCE_NAME`, `AWS_*`, `*_API_KEY`). It does not make network
requests. The configurator merges into your `opencode.json`, preserves
unrelated keys, and refuses to clobber an existing `model` pin without
`--force`.

## `private_local` — full privacy

**What "private" means here:** prompts, code, and tool output never leave the
machine running OpenCode. The wizard's hooks are bash and the plugin shim is
local JS — nothing in this repo phones home.

Supported runtimes (all open-weight, locally hosted):

| Runtime | Default URL | Suggested model |
|---------|-------------|------------------|
| **Ollama** | `http://localhost:11434/v1` | `qwen3-coder:30b` (16–24 GB VRAM) |
| **LM Studio** | `http://127.0.0.1:1234/v1` | Whatever you've loaded in the GUI |
| **llama.cpp** | `http://127.0.0.1:8080/v1` | Any GGUF you've loaded |
| **vLLM** | `http://127.0.0.1:8000/v1` | Any HuggingFace ID you serve |
| **MLX** (Apple Silicon native) | `http://127.0.0.1:8080/v1` | `mlx-community/Qwen2.5-Coder-32B-Instruct-4bit` (32 GB unified memory) |

**Capability floor.** SDLC enforcement (plan → TDD → self-review → cross-model
review) leans on instruction-following + tool-use. The 30B+ code-tuned class
(Qwen2.5-Coder, DeepSeek-Coder) is the local sweet spot. Smaller models
(7–13B) typically fail the full protocol. A failed run on an undersized model
is a capability result, not a wizard bug.

### Ollama walkthrough — the recommended private path

```bash
# Install Ollama (macOS / Linux). See https://ollama.com for Windows.
brew install ollama

# Start the daemon (runs on :11434)
ollama serve &

# Pull a code-tuned 30B+ model (≈19 GB on disk)
ollama pull qwen3-coder:30b

# Configure OpenCode to use it
bash .opencode/scripts/configure-backend.sh \
     --tier private_local --provider ollama \
     --model qwen3-coder:30b

# Start OpenCode in this dir; AGENTS.md auto-loads + plugin runs hooks
opencode
```

Alternatives in the same tier — pick the runtime that matches your hardware
and tooling preference. All four use OpenAI-compatible HTTP, which OpenCode
addresses via `@ai-sdk/openai-compatible`. The configure-backend script
writes the right `provider` block per runtime.

## `enterprise` — your tenant

Prompts go to Azure OpenAI, AWS Bedrock, or an internal AI gateway running
under your contract. Use this when:

- Your company has Azure OpenAI with zero-retention enabled.
- You have AWS Bedrock provisioned and Claude/Titan/Llama is approved.
- You run an internal AI gateway that proxies a hosted model.

```bash
# Azure OpenAI (set AZURE_RESOURCE_NAME and AZURE_API_KEY first)
bash .opencode/scripts/configure-backend.sh \
     --tier enterprise --provider azure_openai \
     --model gpt-4o

# AWS Bedrock (uses your AWS credentials chain)
bash .opencode/scripts/configure-backend.sh \
     --tier enterprise --provider aws_bedrock \
     --model anthropic.claude-sonnet-4-5
```

OpenCode reads keys via `{env:VAR}` substitution; no secrets land in
`opencode.json`.

## `hosted_oss` — open weights, third-party host

Open-weight model on a hosted endpoint. Use when local hardware is
insufficient and an enterprise tenant is unavailable.

| Provider | Suggested model | Notes |
|----------|-----------------|-------|
| Together | `Qwen/Qwen2.5-Coder-32B-Instruct` | Stable, paid hosting |
| Groq | `gpt-oss-120b` | Fastest hosted, free daily quota; OpenAI's open-weights release on Groq's LPU stack |
| OpenRouter | `qwen/qwen-2.5-coder-32b-instruct` | Aggregator routing across providers |
| Cerebras | `gpt-oss-120b` or `qwen-3-235b-a22b-instruct-2507` | Free tier, ~2000 tok/s |
| DeepSeek direct | `deepseek-v4-flash` | Cheapest paid hosted; V4 family shipped 2026-04-24 |
| NVIDIA NIM (`nvidia_nim`) | `deepseek-ai/deepseek-r1` | Free credits at build.nvidia.com |

```bash
# Free path — Cerebras
export CEREBRAS_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier hosted_oss --provider cerebras \
     --model "gpt-oss-120b"

# Cheapest paid — DeepSeek direct
export DEEPSEEK_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier hosted_oss --provider deepseek \
     --model "deepseek-v4-flash"

# Stable paid — Together
export TOGETHER_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier hosted_oss --provider together \
     --model "Qwen/Qwen2.5-Coder-32B-Instruct"
```

The host's logging policy applies. If that's not acceptable for your data,
move to `private_local` or `enterprise`.

## `managed` — OpenCode-routed PAYG (Zen)

OpenCode's own hosted routing service. PAYG with auto-reload, 40+ models
including a free tier (Big Pickle, DeepSeek V4 Flash Free, MiniMax M2.5
Free, Nemotron 3 Super Free). Lowest-friction "just give me something
that works" option per OpenCode's own docs — the recommended new-user
entry point.

| Provider | Default model | Notes |
|----------|---------------|-------|
| OpenCode Zen (`opencode` / `zen` / `opencode_zen`) | `gpt-5.5` | 40+ models, $5 auto-reload trigger, free-tier models available |

```bash
export OPENCODE_ZEN_API_KEY="..."   # get a key at opencode.ai/zen
bash .opencode/scripts/configure-backend.sh \
     --tier managed --provider opencode \
     --model "gpt-5.5"

# Or use a free-tier model for $0 work:
bash .opencode/scripts/configure-backend.sh \
     --tier managed --provider opencode \
     --model "deepseek-v4-flash-free"
```

**Privacy positioning.** Sits between `hosted_oss` and `proprietary`:
prompts go through OpenCode's infra (you don't control the upstream
routing decisions), but you're not directly bound to a specific vendor
contract. Less private than DIY hosted, less locked-in than vendor.

## `proprietary` — max capability, vendor-bound

Anthropic Claude, OpenAI GPT, or Google AI Studio (Gemini). Use when
ceiling matters more than data locality and you accept the vendor's
standard terms. (Gemini lives here despite the "OSS-friendly" branding
because the weights are closed; the runtime is just hosted.)

```bash
# Anthropic
export ANTHROPIC_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier proprietary --provider anthropic \
     --model claude-opus-4-7

# Google AI Studio (Gemini)
export GOOGLE_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier proprietary --provider google_aistudio \
     --model gemini-3.1-pro
```

Plus Z.AI GLM Coding Plan (post-Anthropic-OAuth-ban migration target):

```bash
export ZAI_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier proprietary --provider zai \
     --model glm-4.6
```

## `subscription` — OAuth-managed sub bridge (Copilot Pro+)

The only subscription path that bridges Claude Opus 4.7 + GPT-5.3-Codex
into OpenCode as of May 2026. Anthropic killed third-party OAuth in
Jan/Feb 2026 (OpenCode removed the OAuth code March 2026); GitHub
Copilot Pro+ ($39/mo) is now the lone whitelisted bridge.

Critical shape difference from every other tier: **auth is OAuth, not
an API key**. No env var goes into `opencode.json`; the wizard scaffolds
the model pin and OpenCode's native `github-copilot` adapter handles the
device-flow OAuth on first use.

| Provider | Default model | Notes |
|----------|---------------|-------|
| GitHub Copilot (`github-copilot` / `copilot` / `gh-copilot`) | `claude-opus-4-7` | $39/mo for Pro+ unlocks Opus + GPT-5.3-Codex; auth via `/connect` in OpenCode |

```bash
# Scaffold the pin (no env var needed — wizard writes the model field):
bash .opencode/scripts/configure-backend.sh \
     --tier subscription --provider copilot \
     --model claude-opus-4-7

# Complete OAuth (one-time per machine):
opencode    # → /connect → search "GitHub Copilot" → enter the code
            #   at github.com/login/device
```

**Privacy positioning.** Prompts go to GitHub/Microsoft/OpenAI/Anthropic
via Copilot's routing under the Pro+ contract. Their terms apply; Copilot
specifically does not train on Pro+ prompts per their docs (verify at the
plan page — pricing and ToS change frequently).

## What the wizard itself sends

Nothing automatic. The plugin shim, hooks, and skills run locally in the
OpenCode process. The only network traffic from this wizard is whatever
backend you pick — and `private_local` adds zero additional traffic.

## Verifying the private path

After configuring `private_local`:

```bash
# Confirm OpenCode resolved to the local provider
opencode debug config | grep -iE '"model"|"provider"' | head -10

# Watch local connections (should show only :11434 / :1234 / :8080 / :8000)
lsof -i -P -n -p "$(pgrep -f opencode | head -1)" 2>/dev/null \
  | grep -i tcp
```

If you see traffic to `api.anthropic.com`, `api.openai.com`, or any cloud
endpoint while in `private_local`, the model field in `opencode.json` was not
applied — re-run `configure-backend.sh --force` and restart OpenCode.

## Limits of this wizard's privacy claims

- We control the bash hooks and the JS plugin shim. We do not control
  OpenCode itself, your OS, or the runtime you point it at.
- "No telemetry from the wizard" does not mean "no telemetry from anything."
  Confirm OpenCode's own telemetry settings if that matters to you.
- The `enterprise` tier is only as private as your tenant's retention policy.
  Verify the contract before assuming zero-retention.

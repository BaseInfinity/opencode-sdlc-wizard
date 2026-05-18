# Privacy Tiers — Choosing a Backend

OpenCode SDLC Wizard supports four backend tiers. Tiers are ordered by where
your prompts and code can travel. The wizard's recommendation defaults to the
strongest privacy guarantee available, not the strongest model ceiling.

| Tier | Where prompts travel | Best for |
|------|----------------------|----------|
| **`private_local`** | Stays on your machine. No outbound traffic. | Privileged data, attorney-client work, air-gapped environments, source you cannot send to a third party |
| **`enterprise`** | Stays in your tenant. Vendor processes under contract; zero-retention configurable. | Regulated companies with an Azure/Bedrock/internal-gateway agreement that meets compliance |
| **`hosted_oss`** | Sent to a third-party host of open-weight models. Logging policy is the host's. | Cost-sensitive work where the model weights are open but you'd rather pay-per-token than self-host |
| **`proprietary`** | Sent to Anthropic / OpenAI. Vendor's standard ToS applies. | Maximum capability ceiling when privacy isn't the binding constraint |

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
| Groq | `llama-3.3-70b-versatile` | Fastest hosted, free daily quota |
| OpenRouter | `qwen/qwen-2.5-coder-32b-instruct` | Aggregator routing across providers |
| Cerebras | `gpt-oss-120b` or `qwen-3-235b-a22b-instruct-2507` | Free tier, ~2000 tok/s |
| DeepSeek direct | `deepseek-chat` | Cheapest paid hosted (~$0.14/M cache-miss) |
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
     --model "deepseek-chat"

# Stable paid — Together
export TOGETHER_API_KEY="..."
bash .opencode/scripts/configure-backend.sh \
     --tier hosted_oss --provider together \
     --model "Qwen/Qwen2.5-Coder-32B-Instruct"
```

The host's logging policy applies. If that's not acceptable for your data,
move to `private_local` or `enterprise`.

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

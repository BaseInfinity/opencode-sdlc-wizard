#!/usr/bin/env bash
# Detect available OpenCode backends across the four privacy tiers.
#
# Output: JSON to stdout with the shape:
# {
#   "private_local":  { ollama, lm_studio, llama_cpp, vllm, mlx },
#   "enterprise":     { azure_openai, aws_bedrock },
#   "hosted_oss":     { together, groq, openrouter, cerebras, deepseek, nvidia_nim },
#   "proprietary":    { anthropic, openai, google_aistudio, zai },
#   "managed":        { opencode (OpenCode Zen) },
#   "subscription":   { github-copilot, openai (ChatGPT Plus/Pro), xai (SuperGrok)
#                       — all OAuth-managed, no auto-detect },
#   "recommendation": "<tier>/<provider>"
# }
#
# Recommendation prefers private_local (data never leaves the machine), then
# enterprise (your tenant), then hosted_oss (open weights via third-party),
# then proprietary (max capability, vendor-bound). When a higher tier has a
# usable backend the lower tier is not recommended even if also available —
# privacy ranks above ceiling for this wizard's purposes.
#
# Pure env probe + PATH check. No live network calls. Safe in CI / sandbox.
#
# Flags:
#   --free-tier-first   Bias the recommendation cascade toward providers with
#                       generous free tiers (NVIDIA NIM, Cerebras, Groq, Google
#                       AI Studio, OpenRouter :free) before paid hosted/proprietary.
#                       Local tier still wins (free + private). Same effect as
#                       env DETECT_FREE_TIER_FIRST=1.
#   --help              Print this header and exit.

set -euo pipefail

while [ $# -gt 0 ]; do
  case "$1" in
    --free-tier-first) DETECT_FREE_TIER_FIRST=1 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Detection helpers -----------------------------------------------------------

bool_str() { if [ "$1" = "1" ] || [ "$1" = "true" ]; then echo "true"; else echo "false"; fi; }

has_cmd() { command -v "$1" >/dev/null 2>&1 && echo "true" || echo "false"; }

env_set() { [ -n "${!1:-}" ] && echo "true" || echo "false"; }

# List Ollama models if ollama is on PATH. Empty array if absent or list fails.
ollama_models_json() {
  if ! command -v ollama >/dev/null 2>&1; then
    echo "[]"
    return
  fi
  # `ollama list` prints a header line + tab-separated rows. First column is
  # the model name. We tolerate stub scripts in tests as well.
  local out
  out="$(ollama list 2>/dev/null | awk 'NR>1 && NF>0 { print $1 }' | head -20)"
  if [ -z "$out" ]; then
    echo "[]"
    return
  fi
  printf '['
  local first=1
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if [ "$first" = "1" ]; then first=0; else printf ','; fi
    printf '"%s"' "$(printf '%s' "$m" | sed 's/"/\\"/g')"
  done <<< "$out"
  printf ']'
}

# Probe each backend ----------------------------------------------------------

# Private/local — runtime presence + (best-effort) running check
P_OLLAMA_INSTALLED="$(has_cmd ollama)"
P_OLLAMA_MODELS="$(ollama_models_json)"
P_LMS_INSTALLED="$(has_cmd lms)"
if [ "$P_LMS_INSTALLED" = "false" ] && [ -d "$HOME/.cache/lm-studio" ]; then
  P_LMS_INSTALLED="true"
fi
P_LLAMACPP_INSTALLED="false"
for b in llama-cli llama-server llama; do
  if command -v "$b" >/dev/null 2>&1; then P_LLAMACPP_INSTALLED="true"; break; fi
done
P_VLLM_INSTALLED="$(has_cmd vllm)"
# MLX runs on Apple Silicon natively. Detection: mlx_lm.generate or mlx-lm
# entry on PATH, or the mlx_lm Python package installed.
P_MLX_INSTALLED="false"
if command -v mlx_lm.generate >/dev/null 2>&1 || command -v mlx-lm >/dev/null 2>&1; then
  P_MLX_INSTALLED="true"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import mlx_lm' >/dev/null 2>&1; then
  P_MLX_INSTALLED="true"
fi

# Enterprise — env-var presence
E_AZURE_SET="$(env_set AZURE_RESOURCE_NAME)"
E_BEDROCK_SET="false"
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] || [ -n "${AWS_PROFILE:-}" ] || [ -n "${AWS_BEARER_TOKEN_BEDROCK:-}" ]; then
  E_BEDROCK_SET="true"
fi

# Hosted OSS — env-var presence
H_TOGETHER_SET="$(env_set TOGETHER_API_KEY)"
H_GROQ_SET="$(env_set GROQ_API_KEY)"
H_OPENROUTER_SET="$(env_set OPENROUTER_API_KEY)"
H_CEREBRAS_SET="$(env_set CEREBRAS_API_KEY)"
H_DEEPSEEK_SET="$(env_set DEEPSEEK_API_KEY)"
# NVIDIA NIM and Google AI Studio: canonical env names only. Older docs
# referenced NIM_API_KEY / GEMINI_API_KEY but accepting alternates while
# the configurator only emits {env:NVIDIA_API_KEY}/{env:GOOGLE_API_KEY}
# would silently produce configs that fail auth at runtime (codex round-1
# F2). One canonical name per provider, surfaced in the JSON output.
H_NVIDIA_SET="$(env_set NVIDIA_API_KEY)"
H_GOOGLE_AISTUDIO_SET="$(env_set GOOGLE_API_KEY)"

# Proprietary — env-var presence
PR_ANTHROPIC_SET="$(env_set ANTHROPIC_API_KEY)"
PR_OPENAI_SET="$(env_set OPENAI_API_KEY)"
# v0.11.0: Z.AI GLM Coding Plan. Closed weights → proprietary tier.
PR_ZAI_SET="$(env_set ZAI_API_KEY)"
# v0.12.0: OpenCode Zen — managed tier. PAYG, OpenCode's hosted routing
# service over 40+ models with a free tier. New 5th privacy tier
# between hosted_oss and proprietary: it's vendor-managed (you don't
# pick the upstream provider, Zen routes for you) but your prompts go
# through OpenCode's infra, not Anthropic/OpenAI direct.
M_OPENCODE_ZEN_SET="$(env_set OPENCODE_ZEN_API_KEY)"

# Recommendation cascade — privacy-first by default. When DETECT_FREE_TIER_FIRST=1
# (set by configure-backend.sh's --free-tier-first), bias toward providers with
# generous free tiers before falling through to paid hosted/proprietary. Local
# private tier still wins both cascades since it's both privacy-max and free.
recommend_privacy_first() {
  if [ "$P_OLLAMA_INSTALLED" = "true" ]; then echo "private_local/ollama"; return; fi
  if [ "$P_LMS_INSTALLED" = "true" ]; then echo "private_local/lm_studio"; return; fi
  if [ "$P_MLX_INSTALLED" = "true" ]; then echo "private_local/mlx"; return; fi
  if [ "$P_LLAMACPP_INSTALLED" = "true" ]; then echo "private_local/llama_cpp"; return; fi
  if [ "$P_VLLM_INSTALLED" = "true" ]; then echo "private_local/vllm"; return; fi
  if [ "$E_AZURE_SET" = "true" ]; then echo "enterprise/azure_openai"; return; fi
  if [ "$E_BEDROCK_SET" = "true" ]; then echo "enterprise/aws_bedrock"; return; fi
  if [ "$H_TOGETHER_SET" = "true" ]; then echo "hosted_oss/together"; return; fi
  if [ "$H_GROQ_SET" = "true" ]; then echo "hosted_oss/groq"; return; fi
  if [ "$H_CEREBRAS_SET" = "true" ]; then echo "hosted_oss/cerebras"; return; fi
  if [ "$H_NVIDIA_SET" = "true" ]; then echo "hosted_oss/nvidia_nim"; return; fi
  if [ "$H_DEEPSEEK_SET" = "true" ]; then echo "hosted_oss/deepseek"; return; fi
  if [ "$H_OPENROUTER_SET" = "true" ]; then echo "hosted_oss/openrouter"; return; fi
  # managed tier (OpenCode Zen) sits between hosted_oss and proprietary in
  # the privacy-first cascade: prompts go through OpenCode's hosted infra
  # (less private than DIY hosted, more managed than your own vendor key).
  if [ "$M_OPENCODE_ZEN_SET" = "true" ]; then echo "managed/opencode"; return; fi
  if [ "$PR_ANTHROPIC_SET" = "true" ]; then echo "proprietary/anthropic"; return; fi
  if [ "$PR_OPENAI_SET" = "true" ]; then echo "proprietary/openai"; return; fi
  if [ "$H_GOOGLE_AISTUDIO_SET" = "true" ]; then echo "proprietary/google_aistudio"; return; fi
  if [ "$PR_ZAI_SET" = "true" ]; then echo "proprietary/zai"; return; fi
  echo "none"
}

# Free-tier-first: keep local at top (still free + private), then prefer
# providers with generous free tiers (NIM credits, Cerebras free, Groq free
# daily, Google AI Studio quota, OpenRouter :free models) before paid hosted
# (Together, DeepSeek-direct) and finally paid proprietary.
recommend_free_tier_first() {
  if [ "$P_OLLAMA_INSTALLED" = "true" ]; then echo "private_local/ollama"; return; fi
  if [ "$P_LMS_INSTALLED" = "true" ]; then echo "private_local/lm_studio"; return; fi
  if [ "$P_MLX_INSTALLED" = "true" ]; then echo "private_local/mlx"; return; fi
  if [ "$P_LLAMACPP_INSTALLED" = "true" ]; then echo "private_local/llama_cpp"; return; fi
  if [ "$P_VLLM_INSTALLED" = "true" ]; then echo "private_local/vllm"; return; fi
  if [ "$H_NVIDIA_SET" = "true" ]; then echo "hosted_oss/nvidia_nim"; return; fi
  if [ "$H_CEREBRAS_SET" = "true" ]; then echo "hosted_oss/cerebras"; return; fi
  if [ "$H_GROQ_SET" = "true" ]; then echo "hosted_oss/groq"; return; fi
  if [ "$H_GOOGLE_AISTUDIO_SET" = "true" ]; then echo "proprietary/google_aistudio"; return; fi
  if [ "$H_OPENROUTER_SET" = "true" ]; then echo "hosted_oss/openrouter"; return; fi
  if [ "$H_DEEPSEEK_SET" = "true" ]; then echo "hosted_oss/deepseek"; return; fi
  if [ "$H_TOGETHER_SET" = "true" ]; then echo "hosted_oss/together"; return; fi
  if [ "$E_AZURE_SET" = "true" ]; then echo "enterprise/azure_openai"; return; fi
  if [ "$E_BEDROCK_SET" = "true" ]; then echo "enterprise/aws_bedrock"; return; fi
  # Z.AI Coding Plan goes here in the free-cascade — paid sub but the
  # community signal (May-2026 post-OAuth-ban migration target) ranks it
  # above the other proprietary tiers when cost matters more than ceiling.
  if [ "$PR_ZAI_SET" = "true" ]; then echo "proprietary/zai"; return; fi
  # OpenCode Zen also goes here — has a free tier (Big Pickle, DeepSeek
  # V4 Flash Free, MiniMax M2.5 Free, Nemotron 3 Super Free) so it
  # beats paid-per-token Anthropic/OpenAI on cost.
  if [ "$M_OPENCODE_ZEN_SET" = "true" ]; then echo "managed/opencode"; return; fi
  if [ "$PR_ANTHROPIC_SET" = "true" ]; then echo "proprietary/anthropic"; return; fi
  if [ "$PR_OPENAI_SET" = "true" ]; then echo "proprietary/openai"; return; fi
  echo "none"
}

if [ "${DETECT_FREE_TIER_FIRST:-0}" = "1" ]; then
  RECOMMENDATION="$(recommend_free_tier_first)"
else
  RECOMMENDATION="$(recommend_privacy_first)"
fi

# Emit JSON -------------------------------------------------------------------

cat <<EOF
{
  "private_local": {
    "ollama":    { "installed": $P_OLLAMA_INSTALLED, "models": $P_OLLAMA_MODELS },
    "lm_studio": { "installed": $P_LMS_INSTALLED },
    "llama_cpp": { "installed": $P_LLAMACPP_INSTALLED },
    "vllm":      { "installed": $P_VLLM_INSTALLED },
    "mlx":       { "installed": $P_MLX_INSTALLED }
  },
  "enterprise": {
    "azure_openai": { "key_set": $E_AZURE_SET, "env": "AZURE_RESOURCE_NAME" },
    "aws_bedrock":  { "key_set": $E_BEDROCK_SET, "envs": ["AWS_ACCESS_KEY_ID","AWS_PROFILE","AWS_BEARER_TOKEN_BEDROCK"] }
  },
  "hosted_oss": {
    "together":   { "key_set": $H_TOGETHER_SET,   "env": "TOGETHER_API_KEY" },
    "groq":       { "key_set": $H_GROQ_SET,       "env": "GROQ_API_KEY" },
    "openrouter": { "key_set": $H_OPENROUTER_SET, "env": "OPENROUTER_API_KEY" },
    "cerebras":   { "key_set": $H_CEREBRAS_SET,   "env": "CEREBRAS_API_KEY" },
    "deepseek":   { "key_set": $H_DEEPSEEK_SET,   "env": "DEEPSEEK_API_KEY" },
    "nvidia_nim": { "key_set": $H_NVIDIA_SET,     "env": "NVIDIA_API_KEY" }
  },
  "proprietary": {
    "anthropic":       { "key_set": $PR_ANTHROPIC_SET,       "env": "ANTHROPIC_API_KEY" },
    "openai":          { "key_set": $PR_OPENAI_SET,          "env": "OPENAI_API_KEY" },
    "google_aistudio": { "key_set": $H_GOOGLE_AISTUDIO_SET,  "env": "GOOGLE_API_KEY" },
    "zai":             { "key_set": $PR_ZAI_SET,             "env": "ZAI_API_KEY" }
  },
  "managed": {
    "opencode": { "key_set": $M_OPENCODE_ZEN_SET, "env": "OPENCODE_ZEN_API_KEY" }
  },
  "subscription": {
    "github-copilot": { "key_set": false, "env": null, "auth": "oauth", "setup": "opencode /connect → github.com/login/device" },
    "openai":         { "key_set": false, "env": null, "auth": "oauth", "setup": "opencode /connect → browser OpenAI login (ChatGPT Plus/Pro)" },
    "xai":            { "key_set": false, "env": null, "auth": "oauth", "setup": "opencode /connect → browser xAI login (SuperGrok) or device-code" }
  },
  "recommendation": "$RECOMMENDATION"
}
EOF

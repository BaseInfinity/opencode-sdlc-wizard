#!/usr/bin/env bash
# Detect available OpenCode backends across the four privacy tiers.
#
# Output: JSON to stdout with the shape:
# {
#   "private_local":  { ollama, lm_studio, llama_cpp, vllm },
#   "enterprise":     { azure_openai, aws_bedrock },
#   "hosted_oss":     { together, groq, openrouter },
#   "proprietary":    { anthropic, openai },
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

set -euo pipefail

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

# Proprietary — env-var presence
PR_ANTHROPIC_SET="$(env_set ANTHROPIC_API_KEY)"
PR_OPENAI_SET="$(env_set OPENAI_API_KEY)"

# Recommendation: privacy-first cascade
recommend() {
  if [ "$P_OLLAMA_INSTALLED" = "true" ]; then echo "private_local/ollama"; return; fi
  if [ "$P_LMS_INSTALLED" = "true" ]; then echo "private_local/lm_studio"; return; fi
  if [ "$P_LLAMACPP_INSTALLED" = "true" ]; then echo "private_local/llama_cpp"; return; fi
  if [ "$P_VLLM_INSTALLED" = "true" ]; then echo "private_local/vllm"; return; fi
  if [ "$E_AZURE_SET" = "true" ]; then echo "enterprise/azure_openai"; return; fi
  if [ "$E_BEDROCK_SET" = "true" ]; then echo "enterprise/aws_bedrock"; return; fi
  if [ "$H_TOGETHER_SET" = "true" ]; then echo "hosted_oss/together"; return; fi
  if [ "$H_GROQ_SET" = "true" ]; then echo "hosted_oss/groq"; return; fi
  if [ "$H_OPENROUTER_SET" = "true" ]; then echo "hosted_oss/openrouter"; return; fi
  if [ "$PR_ANTHROPIC_SET" = "true" ]; then echo "proprietary/anthropic"; return; fi
  if [ "$PR_OPENAI_SET" = "true" ]; then echo "proprietary/openai"; return; fi
  echo "none"
}
RECOMMENDATION="$(recommend)"

# Emit JSON -------------------------------------------------------------------

cat <<EOF
{
  "private_local": {
    "ollama":    { "installed": $P_OLLAMA_INSTALLED, "models": $P_OLLAMA_MODELS },
    "lm_studio": { "installed": $P_LMS_INSTALLED },
    "llama_cpp": { "installed": $P_LLAMACPP_INSTALLED },
    "vllm":      { "installed": $P_VLLM_INSTALLED }
  },
  "enterprise": {
    "azure_openai": { "key_set": $E_AZURE_SET, "env": "AZURE_RESOURCE_NAME" },
    "aws_bedrock":  { "key_set": $E_BEDROCK_SET, "envs": ["AWS_ACCESS_KEY_ID","AWS_PROFILE","AWS_BEARER_TOKEN_BEDROCK"] }
  },
  "hosted_oss": {
    "together":   { "key_set": $H_TOGETHER_SET, "env": "TOGETHER_API_KEY" },
    "groq":       { "key_set": $H_GROQ_SET, "env": "GROQ_API_KEY" },
    "openrouter": { "key_set": $H_OPENROUTER_SET, "env": "OPENROUTER_API_KEY" }
  },
  "proprietary": {
    "anthropic": { "key_set": $PR_ANTHROPIC_SET, "env": "ANTHROPIC_API_KEY" },
    "openai":    { "key_set": $PR_OPENAI_SET, "env": "OPENAI_API_KEY" }
  },
  "recommendation": "$RECOMMENDATION"
}
EOF

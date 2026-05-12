#!/usr/bin/env bash
# pick-backend.sh — one-shot detect→configure orchestrator (v0.9.0).
#
# Runs detect-backends.sh, parses its `recommendation` field, resolves a
# canonical default model for the detected tier/provider, and invokes
# configure-backend.sh. The two-step picker workflow (detect + configure)
# becomes a single command for first-time consumers.
#
# Usage:
#   pick-backend.sh [--free-tier-first]
#                   [--tier <tier>] [--provider <id>] [--model <name>]
#                   [--target-dir <path>] [--force] [--dry-run]
#
# --free-tier-first   Bias detector toward providers with generous free
#                     tiers (Cerebras, Groq, NIM, Google AI Studio) before
#                     paid hosted/proprietary. Local tier still wins both.
# --tier              Override the detected tier.
# --provider          Override the detected provider id.
# --model             Override the canonical default model for the resolved
#                     tier/provider. Without this, pick uses the floor model
#                     from the lookup table.
# --target-dir PATH   Pass through to configure-backend.sh (default: cwd).
# --force             Pass through (overwrites existing opencode.json model).
# --dry-run           Pass through as --print-only — configurator prints the
#                     merged JSON but does not write the file.
#
# Exit codes:
#   0  configured
#   2  bad args
#   3  detector returned "none" recommendation and no --tier/--provider given
#   4  no default model known for resolved tier/provider (pass --model)
#   other  configurator's own exit code

set -euo pipefail

usage() {
  sed -n '2,30p' "$0"
}

TIER=""
PROVIDER=""
MODEL=""
TARGET_DIR=""
FORCE=0
DRY_RUN=0
FREE_TIER_FIRST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) shift; TIER="${1:-}" ;;
    --tier=*) TIER="${1#*=}" ;;
    --provider) shift; PROVIDER="${1:-}" ;;
    --provider=*) PROVIDER="${1#*=}" ;;
    --model) shift; MODEL="${1:-}" ;;
    --model=*) MODEL="${1#*=}" ;;
    --target-dir) shift; TARGET_DIR="${1:-}" ;;
    --target-dir=*) TARGET_DIR="${1#*=}" ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --free-tier-first) FREE_TIER_FIRST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Locate sibling scripts. Prefer PATH (test stubs + user overrides), fall
# back to the .opencode/scripts/ layout where pick is installed alongside
# detect/configure. PATH-first means tests can shim either script and
# pick will respect the shim; production users don't typically have
# .opencode/scripts/ on PATH, so the fallback wins.
HERE="$(cd "$(dirname "$0")" && pwd)"
if command -v detect-backends.sh >/dev/null 2>&1; then
  DETECT="$(command -v detect-backends.sh)"
elif [ -x "$HERE/detect-backends.sh" ]; then
  DETECT="$HERE/detect-backends.sh"
else
  echo "detect-backends.sh not found on PATH or next to pick-backend.sh" >&2
  exit 2
fi
if command -v configure-backend.sh >/dev/null 2>&1; then
  CONFIGURE="$(command -v configure-backend.sh)"
elif [ -x "$HERE/configure-backend.sh" ]; then
  CONFIGURE="$HERE/configure-backend.sh"
else
  echo "configure-backend.sh not found on PATH or next to pick-backend.sh" >&2
  exit 2
fi

# If tier+provider both supplied, skip the detector run entirely.
if [ -z "$TIER" ] || [ -z "$PROVIDER" ]; then
  if [ "$FREE_TIER_FIRST" = "1" ]; then
    JSON="$(DETECT_FREE_TIER_FIRST=1 "$DETECT")"
  else
    JSON="$("$DETECT")"
  fi
  REC="$(printf '%s' "$JSON" \
        | grep -oE '"recommendation"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 \
        | sed -E 's/.*"recommendation"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  if [ "$REC" = "none" ] || [ -z "$REC" ]; then
    echo "pick: no backend detected." >&2
    echo "  Either set an API key env var (TOGETHER_API_KEY, CEREBRAS_API_KEY," >&2
    echo "  DEEPSEEK_API_KEY, NVIDIA_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY," >&2
    echo "  OPENAI_API_KEY) or install a local runtime (Ollama / LM Studio /" >&2
    echo "  llama.cpp / vLLM / MLX), then re-run pick." >&2
    echo "  Or override directly:  pick --tier <tier> --provider <id>" >&2
    exit 3
  fi
  [ -z "$TIER" ]     && TIER="${REC%%/*}"
  [ -z "$PROVIDER" ] && PROVIDER="${REC#*/}"
fi

# Default-model lookup. Single source of truth for the canonical floor
# model per tier/provider — referenced by docs (cost-ladder.md) and
# tested for drift in test-pick.sh T12.
if [ -z "$MODEL" ]; then
  case "$TIER/$PROVIDER" in
    private_local/ollama)         MODEL="qwen2.5-coder:32b" ;;
    private_local/mlx)            MODEL="mlx-community/Qwen2.5-Coder-32B-Instruct-4bit" ;;
    private_local/lm_studio|private_local/lmstudio)
                                  MODEL="qwen2.5-coder-32b-instruct" ;;
    private_local/llama_cpp|private_local/llamacpp)
                                  MODEL="qwen2.5-coder-32b-instruct" ;;
    private_local/vllm)           MODEL="Qwen/Qwen2.5-Coder-32B-Instruct" ;;
    enterprise/azure_openai|enterprise/azure)
                                  MODEL="gpt-5" ;;
    enterprise/aws_bedrock|enterprise/bedrock|enterprise/amazon-bedrock)
                                  MODEL="anthropic.claude-sonnet-4-5-20250929-v1:0" ;;
    hosted_oss/together|hosted_oss/togetherai)
                                  MODEL="Qwen/Qwen2.5-Coder-32B-Instruct" ;;
    hosted_oss/groq)              MODEL="llama-3.3-70b-versatile" ;;
    hosted_oss/openrouter)        MODEL="qwen/qwen-2.5-coder-32b-instruct" ;;
    hosted_oss/cerebras)          MODEL="gpt-oss-120b" ;;
    hosted_oss/deepseek)          MODEL="deepseek-chat" ;;
    hosted_oss/nvidia_nim|hosted_oss/nvidia|hosted_oss/nvidia-nim)
                                  MODEL="deepseek-ai/deepseek-r1" ;;
    proprietary/anthropic)        MODEL="claude-opus-4-7" ;;
    proprietary/openai)           MODEL="gpt-5" ;;
    proprietary/google_aistudio|proprietary/google|proprietary/gemini)
                                  MODEL="gemini-2.5-flash" ;;
    *)
      echo "pick: no default model known for $TIER/$PROVIDER." >&2
      echo "  Pass --model <name> explicitly, or check docs/cost-ladder.md" >&2
      echo "  for the canonical model id for this provider." >&2
      exit 4
      ;;
  esac
fi

# Forward to configure-backend.sh. --dry-run becomes --print-only on the
# configurator (it prints the merged JSON but does not write the file).
CONFIGURE_ARGS=(--tier "$TIER" --provider "$PROVIDER" --model "$MODEL")
[ -n "$TARGET_DIR" ] && CONFIGURE_ARGS+=(--target-dir "$TARGET_DIR")
[ "$FORCE" = "1" ]   && CONFIGURE_ARGS+=(--force)
[ "$DRY_RUN" = "1" ] && CONFIGURE_ARGS+=(--print-only)

echo "pick: resolved $TIER/$PROVIDER → $MODEL" >&2
"$CONFIGURE" "${CONFIGURE_ARGS[@]}"

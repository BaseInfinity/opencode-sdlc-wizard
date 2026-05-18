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
# v0.10.0 Mixed-Mode: optional reviewer model routing. When set, pick
# forwards to configure-backend.sh's --reviewer-* flags so the emitted
# opencode.json gains an agent.review.model block. Per community
# patterns research (May 2026), 11/15 surveyed configs split build vs
# review across different models. Coder/reviewer is the first pair;
# planner/docs follow in later releases.
REVIEWER_TIER=""
REVIEWER_PROVIDER=""
REVIEWER_MODEL=""
# v0.10.2 Planner agent model routing. Symmetric to reviewer; writes
# agent.plan.model + planner provider block. Typical use: plan=small/fast
# (haiku, gpt-5-mini), build=mid (the global), review=high-reasoning.
PLANNER_TIER=""
PLANNER_PROVIDER=""
PLANNER_MODEL=""
# v0.10.4 small_model: global fast/cheap fallback. Same triplet shape;
# writes top-level `small_model` (not under agent.). Per May-17 research,
# 35-40% of community configs set this.
SMALL_TIER=""
SMALL_PROVIDER=""
SMALL_MODEL=""
# v0.10.1 Per-agent permission sandboxing. Passthrough to configure-backend's
# matching flags — canonical permission.write block per agent (test/spec
# files for test-writer, .md only for docs).
SANDBOX_TEST_WRITER=0
SANDBOX_DOCS=0
# v0.10.5 plan-mode tool denial (agent.plan.tools.{write,edit,patch}=false).
SANDBOX_PLAN=0
# v0.11.1 per-agent temperatures.
CODER_TEMP=""
PLANNER_TEMP=""
REVIEWER_TEMP=""
SECURITY_TEMP=""
# v0.11.2 security agent (model triplet + sandbox flag).
SECURITY_TIER=""
SECURITY_PROVIDER=""
SECURITY_MODEL=""
SANDBOX_SECURITY=0

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
    --reviewer-tier) shift; REVIEWER_TIER="${1:-}" ;;
    --reviewer-tier=*) REVIEWER_TIER="${1#*=}" ;;
    --reviewer-provider) shift; REVIEWER_PROVIDER="${1:-}" ;;
    --reviewer-provider=*) REVIEWER_PROVIDER="${1#*=}" ;;
    --reviewer-model) shift; REVIEWER_MODEL="${1:-}" ;;
    --reviewer-model=*) REVIEWER_MODEL="${1#*=}" ;;
    --planner-tier) shift; PLANNER_TIER="${1:-}" ;;
    --planner-tier=*) PLANNER_TIER="${1#*=}" ;;
    --planner-provider) shift; PLANNER_PROVIDER="${1:-}" ;;
    --planner-provider=*) PLANNER_PROVIDER="${1#*=}" ;;
    --planner-model) shift; PLANNER_MODEL="${1:-}" ;;
    --planner-model=*) PLANNER_MODEL="${1#*=}" ;;
    --small-tier) shift; SMALL_TIER="${1:-}" ;;
    --small-tier=*) SMALL_TIER="${1#*=}" ;;
    --small-provider) shift; SMALL_PROVIDER="${1:-}" ;;
    --small-provider=*) SMALL_PROVIDER="${1#*=}" ;;
    --small-model) shift; SMALL_MODEL="${1:-}" ;;
    --small-model=*) SMALL_MODEL="${1#*=}" ;;
    --sandbox-test-writer) SANDBOX_TEST_WRITER=1 ;;
    --sandbox-docs) SANDBOX_DOCS=1 ;;
    --sandbox-plan) SANDBOX_PLAN=1 ;;
    --coder-temp) shift; CODER_TEMP="${1:-}" ;;
    --coder-temp=*) CODER_TEMP="${1#*=}" ;;
    --planner-temp) shift; PLANNER_TEMP="${1:-}" ;;
    --planner-temp=*) PLANNER_TEMP="${1#*=}" ;;
    --reviewer-temp) shift; REVIEWER_TEMP="${1:-}" ;;
    --reviewer-temp=*) REVIEWER_TEMP="${1#*=}" ;;
    --security-temp) shift; SECURITY_TEMP="${1:-}" ;;
    --security-temp=*) SECURITY_TEMP="${1#*=}" ;;
    --security-tier) shift; SECURITY_TIER="${1:-}" ;;
    --security-tier=*) SECURITY_TIER="${1#*=}" ;;
    --security-provider) shift; SECURITY_PROVIDER="${1:-}" ;;
    --security-provider=*) SECURITY_PROVIDER="${1#*=}" ;;
    --security-model) shift; SECURITY_MODEL="${1:-}" ;;
    --security-model=*) SECURITY_MODEL="${1#*=}" ;;
    --sandbox-security) SANDBOX_SECURITY=1 ;;
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
# model per tier/provider — referenced by docs (cost-ladder.md), used for
# both the coder pin and (v0.10.0) the reviewer pin, tested for drift
# in test-pick.sh T12.
default_model_for() {
  case "$1/$2" in
    private_local/ollama)         echo "qwen3-coder:30b" ;;
    private_local/mlx)            echo "mlx-community/Qwen2.5-Coder-32B-Instruct-4bit" ;;
    private_local/lm_studio|private_local/lmstudio)
                                  echo "qwen2.5-coder-32b-instruct" ;;
    private_local/llama_cpp|private_local/llamacpp)
                                  echo "qwen2.5-coder-32b-instruct" ;;
    private_local/vllm)           echo "Qwen/Qwen2.5-Coder-32B-Instruct" ;;
    enterprise/azure_openai|enterprise/azure)
                                  echo "gpt-5" ;;
    enterprise/aws_bedrock|enterprise/bedrock|enterprise/amazon-bedrock)
                                  echo "anthropic.claude-sonnet-4-5-20250929-v1:0" ;;
    hosted_oss/together|hosted_oss/togetherai)
                                  echo "Qwen/Qwen2.5-Coder-32B-Instruct" ;;
    hosted_oss/groq)              echo "gpt-oss-120b" ;;
    hosted_oss/openrouter)        echo "qwen/qwen-2.5-coder-32b-instruct" ;;
    hosted_oss/cerebras)          echo "gpt-oss-120b" ;;
    hosted_oss/deepseek)          echo "deepseek-v4-flash" ;;
    hosted_oss/nvidia_nim|hosted_oss/nvidia|hosted_oss/nvidia-nim)
                                  echo "deepseek-ai/deepseek-r1" ;;
    proprietary/anthropic)        echo "claude-opus-4-7" ;;
    proprietary/openai)           echo "gpt-5.3-codex" ;;
    proprietary/google_aistudio|proprietary/google|proprietary/gemini)
                                  echo "gemini-3.1-pro" ;;
    proprietary/zai|proprietary/z.ai|proprietary/z_ai|proprietary/glm)
                                  echo "glm-4.6" ;;
    managed/opencode|managed/opencode_zen|managed/opencode-zen|managed/zen)
                                  echo "gpt-5.5" ;;
    subscription/github-copilot|subscription/copilot|subscription/github_copilot|subscription/gh-copilot|subscription/gh_copilot)
                                  echo "claude-opus-4-7" ;;
    *) return 1 ;;
  esac
}

if [ -z "$MODEL" ]; then
  MODEL="$(default_model_for "$TIER" "$PROVIDER")" || {
    echo "pick: no default model known for $TIER/$PROVIDER." >&2
    echo "  Pass --model <name> explicitly, or check docs/cost-ladder.md" >&2
    echo "  for the canonical model id for this provider." >&2
    exit 4
  }
fi

# Partial-spec validation: each agent-flag triplet (reviewer, planner)
# is all-or-nothing — partial would silently produce a config without
# the intended routing. Allow tier+provider without model (filled from
# default-model map); reject any other partial combination.
validate_agent_triplet() {
  local label="$1" tier_v="$2" prov_v="$3" model_v="$4"
  if [ -n "$model_v" ] && { [ -z "$tier_v" ] || [ -z "$prov_v" ]; }; then
    echo "pick: --${label}-model requires --${label}-tier and --${label}-provider together" >&2
    exit 2
  fi
  if [ -n "$tier_v" ] && [ -z "$prov_v" ]; then
    echo "pick: --${label}-tier requires --${label}-provider together (all three ${label} flags must be set or none)" >&2
    exit 2
  fi
  if [ -n "$prov_v" ] && [ -z "$tier_v" ]; then
    echo "pick: --${label}-provider requires --${label}-tier together (all three ${label} flags must be set or none)" >&2
    exit 2
  fi
}
validate_agent_triplet "reviewer" "$REVIEWER_TIER" "$REVIEWER_PROVIDER" "$REVIEWER_MODEL"
validate_agent_triplet "planner"  "$PLANNER_TIER"  "$PLANNER_PROVIDER"  "$PLANNER_MODEL"
validate_agent_triplet "small"    "$SMALL_TIER"    "$SMALL_PROVIDER"    "$SMALL_MODEL"
validate_agent_triplet "security" "$SECURITY_TIER" "$SECURITY_PROVIDER" "$SECURITY_MODEL"

# Resolve reviewer-model default if --reviewer-tier + --reviewer-provider
# set but --reviewer-model not. Same default-model map as the coder pin.
if [ -n "$REVIEWER_TIER" ] && [ -n "$REVIEWER_PROVIDER" ] && [ -z "$REVIEWER_MODEL" ]; then
  REVIEWER_MODEL="$(default_model_for "$REVIEWER_TIER" "$REVIEWER_PROVIDER")" || {
    echo "pick: no default model known for reviewer $REVIEWER_TIER/$REVIEWER_PROVIDER." >&2
    echo "  Pass --reviewer-model <name> explicitly." >&2
    exit 4
  }
fi

# Same default-model fallback for the planner side.
if [ -n "$PLANNER_TIER" ] && [ -n "$PLANNER_PROVIDER" ] && [ -z "$PLANNER_MODEL" ]; then
  PLANNER_MODEL="$(default_model_for "$PLANNER_TIER" "$PLANNER_PROVIDER")" || {
    echo "pick: no default model known for planner $PLANNER_TIER/$PLANNER_PROVIDER." >&2
    echo "  Pass --planner-model <name> explicitly." >&2
    exit 4
  }
fi

# Same default-model fallback for the small (cheap/fast) side.
if [ -n "$SMALL_TIER" ] && [ -n "$SMALL_PROVIDER" ] && [ -z "$SMALL_MODEL" ]; then
  SMALL_MODEL="$(default_model_for "$SMALL_TIER" "$SMALL_PROVIDER")" || {
    echo "pick: no default model known for small $SMALL_TIER/$SMALL_PROVIDER." >&2
    echo "  Pass --small-model <name> explicitly." >&2
    exit 4
  }
fi

# Security agent default-model fallback.
if [ -n "$SECURITY_TIER" ] && [ -n "$SECURITY_PROVIDER" ] && [ -z "$SECURITY_MODEL" ]; then
  SECURITY_MODEL="$(default_model_for "$SECURITY_TIER" "$SECURITY_PROVIDER")" || {
    echo "pick: no default model known for security $SECURITY_TIER/$SECURITY_PROVIDER." >&2
    echo "  Pass --security-model <name> explicitly." >&2
    exit 4
  }
fi

# Forward to configure-backend.sh. --dry-run becomes --print-only on the
# configurator (it prints the merged JSON but does not write the file).
CONFIGURE_ARGS=(--tier "$TIER" --provider "$PROVIDER" --model "$MODEL")
[ -n "$TARGET_DIR" ] && CONFIGURE_ARGS+=(--target-dir "$TARGET_DIR")
[ "$FORCE" = "1" ]   && CONFIGURE_ARGS+=(--force)
[ "$DRY_RUN" = "1" ] && CONFIGURE_ARGS+=(--print-only)
if [ -n "$REVIEWER_TIER" ]; then
  CONFIGURE_ARGS+=(
    --reviewer-tier "$REVIEWER_TIER"
    --reviewer-provider "$REVIEWER_PROVIDER"
    --reviewer-model "$REVIEWER_MODEL"
  )
fi
if [ -n "$PLANNER_TIER" ]; then
  CONFIGURE_ARGS+=(
    --planner-tier "$PLANNER_TIER"
    --planner-provider "$PLANNER_PROVIDER"
    --planner-model "$PLANNER_MODEL"
  )
fi
if [ -n "$SMALL_TIER" ]; then
  CONFIGURE_ARGS+=(
    --small-tier "$SMALL_TIER"
    --small-provider "$SMALL_PROVIDER"
    --small-model "$SMALL_MODEL"
  )
fi
[ "$SANDBOX_TEST_WRITER" = "1" ] && CONFIGURE_ARGS+=(--sandbox-test-writer)
[ "$SANDBOX_DOCS" = "1" ]        && CONFIGURE_ARGS+=(--sandbox-docs)
[ "$SANDBOX_PLAN" = "1" ]        && CONFIGURE_ARGS+=(--sandbox-plan)
[ -n "$CODER_TEMP" ]             && CONFIGURE_ARGS+=(--coder-temp "$CODER_TEMP")
[ -n "$PLANNER_TEMP" ]           && CONFIGURE_ARGS+=(--planner-temp "$PLANNER_TEMP")
[ -n "$REVIEWER_TEMP" ]          && CONFIGURE_ARGS+=(--reviewer-temp "$REVIEWER_TEMP")
[ -n "$SECURITY_TEMP" ]          && CONFIGURE_ARGS+=(--security-temp "$SECURITY_TEMP")
if [ -n "$SECURITY_TIER" ]; then
  CONFIGURE_ARGS+=(
    --security-tier "$SECURITY_TIER"
    --security-provider "$SECURITY_PROVIDER"
    --security-model "$SECURITY_MODEL"
  )
fi
[ "$SANDBOX_SECURITY" = "1" ]    && CONFIGURE_ARGS+=(--sandbox-security)

if [ -n "$REVIEWER_TIER" ]; then
  echo "pick: resolved coder $TIER/$PROVIDER → $MODEL + reviewer $REVIEWER_TIER/$REVIEWER_PROVIDER → $REVIEWER_MODEL" >&2
else
  echo "pick: resolved $TIER/$PROVIDER → $MODEL" >&2
fi
"$CONFIGURE" "${CONFIGURE_ARGS[@]}"

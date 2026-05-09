#!/usr/bin/env bash
# Run a cross-model SDLC review through OpenCode using an OSS-tier model
# (DeepSeek-V3 / Qwen2.5-Coder / Llama 3.3 / etc.) instead of Codex.
#
# This is the symmetric path to the codex flow:
#   codex exec --xhigh ... -o .reviews/latest-review.md  "<recheck-prompt>"
# becomes:
#   opencode run --model <provider>/<model> "<recheck-prompt>"  (this script)
#
# The point: remove the Anthropic+OpenAI lock from the SDLC review loop.
# Coder can be anything that hits the capability floor; reviewer can also
# be anything that hits the capability floor. Both can be local (Ollama)
# for zero-egress contexts, or hosted-OSS (Together / Groq / OpenRouter)
# for cost-sensitive contexts.
#
# Usage:
#   cross-model-review.sh \
#     --reviewer-provider <id|alias>  (e.g. togetherai, together, groq, ollama)
#     --reviewer-model <name>         (e.g. deepseek-ai/DeepSeek-V3,
#                                            llama-3.3-70b-versatile,
#                                            qwen2.5-coder:32b)
#     [--reviewer-tier <tier>]        Optional, informational only
#     [--handoff-path PATH]           Default: .reviews/handoff.json
#     [--response-path PATH]          Default: .reviews/response.json
#     [--output-path PATH]            Default: .reviews/latest-review.md
#     [--prompt-extra TEXT]           Optional extra instructions appended
#     [--print-prompt]                Emit the prompt to stdout, do not call opencode
#
# Returns 0 on success, non-zero on any setup or invocation error.
# The reviewer's verdict (CERTIFIED / NOT CERTIFIED + score) lives in the
# output file; the script does not parse it.

set -euo pipefail

REVIEWER_PROVIDER=""
REVIEWER_MODEL=""
REVIEWER_TIER=""
HANDOFF_PATH=".reviews/handoff.json"
RESPONSE_PATH=".reviews/response.json"
OUTPUT_PATH=".reviews/latest-review.md"
PROMPT_EXTRA=""
PRINT_ONLY=0

usage() {
  sed -n '2,30p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --reviewer-provider) shift; REVIEWER_PROVIDER="${1:-}" ;;
    --reviewer-provider=*) REVIEWER_PROVIDER="${1#*=}" ;;
    --reviewer-model) shift; REVIEWER_MODEL="${1:-}" ;;
    --reviewer-model=*) REVIEWER_MODEL="${1#*=}" ;;
    --reviewer-tier) shift; REVIEWER_TIER="${1:-}" ;;
    --reviewer-tier=*) REVIEWER_TIER="${1#*=}" ;;
    --handoff-path) shift; HANDOFF_PATH="${1:-}" ;;
    --handoff-path=*) HANDOFF_PATH="${1#*=}" ;;
    --response-path) shift; RESPONSE_PATH="${1:-}" ;;
    --response-path=*) RESPONSE_PATH="${1#*=}" ;;
    --output-path) shift; OUTPUT_PATH="${1:-}" ;;
    --output-path=*) OUTPUT_PATH="${1#*=}" ;;
    --prompt-extra) shift; PROMPT_EXTRA="${1:-}" ;;
    --prompt-extra=*) PROMPT_EXTRA="${1#*=}" ;;
    --print-prompt) PRINT_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$REVIEWER_PROVIDER" ] || { echo "--reviewer-provider is required" >&2; exit 2; }
[ -n "$REVIEWER_MODEL" ]    || { echo "--reviewer-model is required"    >&2; exit 2; }

# Provider alias resolution: same canonical mapping as configure-backend.sh
case "$REVIEWER_PROVIDER" in
  together|togetherai)              REVIEWER_PROVIDER="togetherai" ;;
  bedrock|aws_bedrock|amazon-bedrock|amazon_bedrock) REVIEWER_PROVIDER="amazon-bedrock" ;;
  azure|azure_openai)               REVIEWER_PROVIDER="azure" ;;
  lm_studio|lmstudio)               REVIEWER_PROVIDER="lmstudio" ;;
  llama_cpp|llamacpp)               REVIEWER_PROVIDER="llamacpp" ;;
  nvidia_nim|nvidia-nim|nvidia)     REVIEWER_PROVIDER="nvidia" ;;
  google_aistudio|google|gemini)    REVIEWER_PROVIDER="google" ;;
  ollama|vllm|groq|openrouter|anthropic|openai|cerebras|deepseek|mlx) ;;  # already canonical
  *) ;;  # pass through unknown ids — opencode will reject if invalid
esac

# Compose the review prompt from handoff + response artifacts. Refuse to
# run without the handoff — without it the reviewer has nothing to check
# against, and silent empty-context reviews are worse than failing fast.
if [ ! -f "$HANDOFF_PATH" ]; then
  echo "Missing $HANDOFF_PATH — cross-model review needs a handoff document." >&2
  echo "Either create one or pass --handoff-path." >&2
  exit 3
fi

PROMPT="CROSS-MODEL SDLC REVIEW (round-N targeted recheck).

Read the following two artifacts:
  - Handoff:  ${HANDOFF_PATH}
  - Response: ${RESPONSE_PATH} (if present)

For each finding the response.json claims FIXED, verify against the
working tree at the cited fix_locations. Do NOT raise new findings
unless P0 on the unchanged round-1 surface.

Run 'npm test' (or the project's documented test command) for
corroboration.

End your output with two literal lines:
  Score: <n>/10
  Certification: CERTIFIED  (or NOT CERTIFIED)
Then a per-finding markdown table."

if [ -n "$PROMPT_EXTRA" ]; then
  PROMPT="$PROMPT

Additional instructions:
$PROMPT_EXTRA"
fi

if [ "$PRINT_ONLY" = "1" ]; then
  printf '%s\n' "$PROMPT"
  exit 0
fi

# Verify opencode is on PATH
if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode not found on PATH. Install with: npm install -g opencode-ai" >&2
  exit 4
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

MODEL_PIN="${REVIEWER_PROVIDER}/${REVIEWER_MODEL}"
echo "Running cross-model review:" >&2
echo "  model:  $MODEL_PIN" >&2
echo "  output: $OUTPUT_PATH" >&2
[ -n "$REVIEWER_TIER" ] && echo "  tier:   $REVIEWER_TIER" >&2

# Run opencode with the chosen model + the review prompt. opencode's `run`
# subcommand prints to stdout; we redirect to the output file so we get
# a clean review artifact symmetric to `codex exec -o`.
opencode run --model "$MODEL_PIN" "$PROMPT" </dev/null > "$OUTPUT_PATH" 2>&1

RC=$?
echo "" >&2
echo "Review written to $OUTPUT_PATH (opencode exit code $RC)." >&2
exit "$RC"

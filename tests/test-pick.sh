#!/usr/bin/env bash
# Tests for scripts/pick-backend.sh — one-shot detect→configure picker.
#
# v0.9.0: `opencode-sdlc-wizard pick` collapses the two-step workflow
#   bash .opencode/scripts/detect-backends.sh
#   bash .opencode/scripts/configure-backend.sh --tier ... --provider ... --model ...
# into a single command. pick runs the detector, parses the
# `recommendation` field, resolves a canonical default model for the
# detected provider, and invokes the configurator.
#
# Tests stub detect-backends.sh and configure-backend.sh on PATH so we
# can control the cascade output and assert what pick forwards.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pick-backend.sh"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pick-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Build a test target with stubs that record their args. The detector stub
# emits a fixed JSON recommendation set by the caller; the configurator
# stub records its args so we can assert pick forwarded the right model
# default for the detected provider.
make_target() {
  local T="$1"
  local DETECT_REC="${2:-private_local/ollama}"
  mkdir -p "$T/stubs"
  cat > "$T/stubs/detect-backends.sh" <<EOF
#!/usr/bin/env bash
# Stub detector. Emits minimal valid JSON with caller-controlled recommendation.
echo "DETECT_ARGS:\$*" >> "\$DETECT_STUB_LOG"
cat <<JSON
{
  "private_local": { "ollama": { "installed": true, "models": [] } },
  "enterprise":    {},
  "hosted_oss":    {},
  "proprietary":   {},
  "recommendation": "$DETECT_REC"
}
JSON
EOF
  chmod +x "$T/stubs/detect-backends.sh"

  cat > "$T/stubs/configure-backend.sh" <<'EOF'
#!/usr/bin/env bash
# Stub configurator. Records args so we can assert pick passed them correctly.
echo "CONFIGURE_ARGS:$*" >> "$CONFIGURE_STUB_LOG"
exit 0
EOF
  chmod +x "$T/stubs/configure-backend.sh"
}

echo "=== pick-backend.sh ==="

# T1: script exists and is executable
if [ -x "$SCRIPT" ]; then
  pass "scripts/pick-backend.sh exists and is executable"
else
  fail "scripts/pick-backend.sh missing or not executable"
fi

# T2: bash syntax check
if [ -f "$SCRIPT" ] && bash -n "$SCRIPT" 2>/dev/null; then
  pass "pick-backend.sh passes bash -n"
else
  fail "pick-backend.sh has syntax errors"
fi

# T3: --help prints usage and exits 0
if [ -x "$SCRIPT" ]; then
  out="$("$SCRIPT" --help 2>&1 || echo SCRIPT_FAILED)"
  if echo "$out" | grep -qiE "(usage|pick)" && echo "$out" | grep -qE -- "--free-tier-first|--tier"; then
    pass "--help prints usage with pick-relevant flags"
  else
    fail "--help missing usage / pick flags"
  fi
fi

# T4: with detector returning private_local/ollama, pick invokes configure
#     with --tier private_local --provider ollama --model qwen3-coder:30b
#     (v0.9.1: bumped from qwen2.5-coder:32b per community-patterns research —
#     Qwen3-Coder shipped Q4 2025, is the most-shared local config in surveyed
#     opencode.json examples, and the qwen3-coder:30b tag is published on
#     ollama.com/library/qwen3-coder/tags.)
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t4"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] \
     && grep -q -- "--tier private_local" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--provider ollama" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--model qwen3-coder:30b" "$CONFIGURE_STUB_LOG"; then
    pass "private_local/ollama → configure --model qwen3-coder:30b"
  else
    fail "private_local/ollama did NOT forward expected args"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T5: --free-tier-first sets DETECT_FREE_TIER_FIRST=1 in detector env
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t5"; make_target "$T" "hosted_oss/cerebras"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  # Modify detector stub to also log DETECT_FREE_TIER_FIRST env value
  cat > "$T/stubs/detect-backends.sh" <<'EOF'
#!/usr/bin/env bash
echo "FREE_TIER_FIRST=${DETECT_FREE_TIER_FIRST:-unset}" >> "$DETECT_STUB_LOG"
cat <<JSON
{
  "private_local": {}, "enterprise": {}, "hosted_oss": {}, "proprietary": {},
  "recommendation": "hosted_oss/cerebras"
}
JSON
EOF
  chmod +x "$T/stubs/detect-backends.sh"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --free-tier-first >/dev/null 2>&1) || true
  if [ -f "$DETECT_STUB_LOG" ] && grep -q "FREE_TIER_FIRST=1" "$DETECT_STUB_LOG"; then
    pass "--free-tier-first sets DETECT_FREE_TIER_FIRST=1 in detector env"
  else
    fail "--free-tier-first did NOT set the env var"
    cat "$DETECT_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T6: --provider override skips detector recommendation
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t6"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --tier hosted_oss --provider cerebras >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] \
     && grep -q -- "--tier hosted_oss" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--provider cerebras" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--model gpt-oss-120b" "$CONFIGURE_STUB_LOG"; then
    pass "--tier/--provider override applies canonical default model (cerebras→gpt-oss-120b)"
  else
    fail "override did NOT pick cerebras default"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T7: --model override wins over canonical default
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t7"; make_target "$T" "hosted_oss/deepseek"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --model deepseek-reasoner >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -q -- "--model deepseek-reasoner" "$CONFIGURE_STUB_LOG"; then
    pass "--model override forwards user's model instead of canonical default"
  else
    fail "--model override was ignored"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T8: detector recommendation "none" → exit non-zero with actionable message
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t8"; make_target "$T" "none"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  rc=0
  out="$(DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
       PATH="$T/stubs:$PATH" "$SCRIPT" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$CONFIGURE_STUB_LOG" ] && echo "$out" | grep -qiE "(no backend|detect|tier|provider)"; then
    pass "detector 'none' → non-zero exit, no configure call, actionable message"
  else
    fail "should have errored on 'none' recommendation (rc=$rc, configure_called=$([ -f "$CONFIGURE_STUB_LOG" ] && echo yes || echo no))"
  fi
fi

# T9: --dry-run passes --print-only to configure (so nothing is written)
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t9"; make_target "$T" "proprietary/anthropic"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --dry-run >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -q -- "--print-only" "$CONFIGURE_STUB_LOG"; then
    pass "--dry-run translates to --print-only on configurator"
  else
    fail "--dry-run did NOT forward as --print-only"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T10: --force passes through to configure
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t10"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --force >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -q -- "--force" "$CONFIGURE_STUB_LOG"; then
    pass "--force passes through to configure-backend.sh"
  else
    fail "--force was dropped"
  fi
fi

# T11: --target-dir passes through to configure
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t11"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  TGT="$T/my-target"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --target-dir "$TGT" >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -q -- "--target-dir $TGT" "$CONFIGURE_STUB_LOG"; then
    pass "--target-dir passes through to configure-backend.sh"
  else
    fail "--target-dir was dropped"
  fi
fi

# T12: default-model map covers every v0.8.x provider — drift gate
# Mirrors the doc-template tests that catch when v0.8.x providers are
# advertised in docs but missing from a code surface.
for combo in \
    "private_local/ollama:qwen" \
    "private_local/mlx:qwen" \
    "private_local/lm_studio:qwen" \
    "private_local/llama_cpp:qwen" \
    "private_local/vllm:Qwen" \
    "hosted_oss/together:Qwen" \
    "hosted_oss/groq:llama" \
    "hosted_oss/openrouter:qwen" \
    "hosted_oss/cerebras:gpt-oss" \
    "hosted_oss/deepseek:deepseek" \
    "hosted_oss/nvidia_nim:deepseek" \
    "proprietary/anthropic:claude" \
    "proprietary/openai:gpt" \
    "proprietary/google_aistudio:gemini"; do
  combo_pair="${combo%%:*}"
  expected_substr="${combo##*:}"
  T="$TMP_ROOT/t12-${combo_pair//\//-}"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  tier="${combo_pair%/*}"
  provider="${combo_pair#*/}"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" --tier "$tier" --provider "$provider" >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -qiE -- "--model [^ ]*${expected_substr}" "$CONFIGURE_STUB_LOG"; then
    pass "default-model map: $tier/$provider → model matches /$expected_substr/"
  else
    fail "default-model map missing for $tier/$provider (expected /$expected_substr/)"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
done

# v0.10.0 Mixed-Mode: pick learns --reviewer-tier / --reviewer-provider /
# --reviewer-model. When --reviewer-tier + --reviewer-provider are given,
# pick resolves the canonical reviewer-model default (from the same map
# used for the coder) if --reviewer-model isn't supplied, then forwards
# all three to configure-backend.sh's matching flags.

# T15: --reviewer-tier + --reviewer-provider forwards reviewer-model default
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t15"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" \
     --reviewer-tier hosted_oss --reviewer-provider cerebras >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] \
     && grep -q -- "--reviewer-tier hosted_oss" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--reviewer-provider cerebras" "$CONFIGURE_STUB_LOG" \
     && grep -q -- "--reviewer-model gpt-oss-120b" "$CONFIGURE_STUB_LOG"; then
    pass "Mixed-Mode: --reviewer-provider cerebras → reviewer-model gpt-oss-120b default"
  else
    fail "Mixed-Mode reviewer default not forwarded correctly"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T16: --reviewer-model override beats canonical reviewer default
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t16"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" \
     --reviewer-tier proprietary --reviewer-provider anthropic \
     --reviewer-model claude-opus-4-7-1m >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && grep -q -- "--reviewer-model claude-opus-4-7-1m" "$CONFIGURE_STUB_LOG"; then
    pass "Mixed-Mode: --reviewer-model override forwards user's reviewer model"
  else
    fail "--reviewer-model override was ignored"
    cat "$CONFIGURE_STUB_LOG" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T17: --reviewer-tier without --reviewer-provider errors (partial spec is a bug)
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t17"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  rc=0
  out="$(DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
       PATH="$T/stubs:$PATH" "$SCRIPT" --reviewer-tier hosted_oss 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qiE "(reviewer|together|all|partial)"; then
    pass "partial --reviewer-* spec rejected with actionable message"
  else
    fail "partial --reviewer-* spec did not error cleanly (rc=$rc)"
  fi
fi

# T18: no --reviewer-* flags → no reviewer args forwarded (regression guard)
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t18"; make_target "$T" "private_local/ollama"
  DETECT_STUB_LOG="$T/detect.log"
  CONFIGURE_STUB_LOG="$T/configure.log"
  (DETECT_STUB_LOG="$DETECT_STUB_LOG" CONFIGURE_STUB_LOG="$CONFIGURE_STUB_LOG" \
   PATH="$T/stubs:$PATH" "$SCRIPT" >/dev/null 2>&1) || true
  if [ -f "$CONFIGURE_STUB_LOG" ] && ! grep -q -- "--reviewer-" "$CONFIGURE_STUB_LOG"; then
    pass "single-mode pick (no --reviewer-*) does NOT forward reviewer flags"
  else
    fail "single-mode pick leaked --reviewer-* args to configure"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All pick-backend tests passed!"

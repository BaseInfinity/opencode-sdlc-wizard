#!/usr/bin/env bash
# Tests for scripts/cross-model-review.sh — runs a cross-model review via
# OpenCode + an OSS-tier model (DeepSeek-V3 / Qwen2.5-Coder / etc.) so the
# SDLC review loop has zero Anthropic+OpenAI dependency.
#
# Tests use a stubbed `opencode` binary on PATH so we don't actually hit a
# remote model.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/cross-model-review.sh"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cmr-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Helper: build a target dir with stub opencode + minimal review inputs
make_target() {
  local T="$1"
  mkdir -p "$T/.reviews" "$T/stubs"
  cat > "$T/.reviews/handoff.json" <<'EOF'
{"review_id":"test-001","round":1,"mission":"Test review","success":"OK","failure":"NOK","files_changed":["foo.js"]}
EOF
  cat > "$T/.reviews/response.json" <<'EOF'
{"review_id":"test-001","round":1,"responses":[{"finding_id":"F1","status":"FIXED","fix_summary":"test fix"}]}
EOF
  # Stub opencode that records its args + emits a fake review verdict
  cat > "$T/stubs/opencode" <<'EOF'
#!/usr/bin/env bash
# Record call to a known location for test assertions
echo "OPENCODE_ARGS:$*" >> "$OPENCODE_STUB_LOG"
# If invoked as `run`, emit a fake verdict to stdout
case "${1:-}" in
  run)
    cat <<EOT

Targeted recheck complete. All findings verified.

Score: 9/10
Certification: CERTIFIED
EOT
    ;;
  *)
    echo "stub-opencode: unknown subcommand $1" >&2
    exit 0
    ;;
esac
EOF
  chmod +x "$T/stubs/opencode"
}

echo "=== cross-model-review.sh ==="

# T1: script exists and is executable
if [ -x "$SCRIPT" ]; then
  pass "scripts/cross-model-review.sh exists and is executable"
else
  fail "scripts/cross-model-review.sh missing or not executable"
fi

# T2: bash syntax check
if [ -f "$SCRIPT" ] && bash -n "$SCRIPT" 2>/dev/null; then
  pass "cross-model-review.sh passes bash -n"
else
  fail "cross-model-review.sh has syntax errors"
fi

# T3: --help prints usage and exits 0
if [ -x "$SCRIPT" ]; then
  out="$("$SCRIPT" --help 2>&1 || echo SCRIPT_FAILED)"
  if echo "$out" | grep -qE "Usage:" && echo "$out" | grep -q "reviewer-provider"; then
    pass "--help prints usage with reviewer-provider flag"
  else
    fail "--help missing usage/reviewer-provider"
  fi
fi

# T4: rejects invocation with no --reviewer-provider / --reviewer-model
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t4"; make_target "$T"
  rc=0
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" "$SCRIPT" >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "rejects invocation without required reviewer flags (rc=$rc)"
  else
    fail "ran without required flags (should rc!=0)"
  fi
fi

# T5: invokes opencode with --model <provider>/<model> when both supplied
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t5"; make_target "$T"
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider togetherai --reviewer-model deepseek-ai/DeepSeek-V3 >/dev/null 2>&1) || true
  if [ -f "$T/stub.log" ] && grep -qE "togetherai/deepseek-ai/DeepSeek-V3" "$T/stub.log"; then
    pass "invokes opencode with --model togetherai/deepseek-ai/DeepSeek-V3"
  else
    fail "stub log missing expected model arg"
    cat "$T/stub.log" 2>/dev/null | head -5 >&2 || true
  fi
fi

# T6: writes review output to .reviews/latest-review.md by default
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t6"; make_target "$T"
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider togetherai --reviewer-model deepseek-ai/DeepSeek-V3 >/dev/null 2>&1) || true
  if [ -f "$T/.reviews/latest-review.md" ] && grep -q "Score:" "$T/.reviews/latest-review.md"; then
    pass "writes review verdict to .reviews/latest-review.md"
  else
    fail "did not write expected review file"
  fi
fi

# T7: --output-path overrides default
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t7"; make_target "$T"
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider groq --reviewer-model llama-3.3-70b-versatile \
              --output-path "$T/custom-review.md" >/dev/null 2>&1) || true
  if [ -f "$T/custom-review.md" ] && [ ! -f "$T/.reviews/latest-review.md" ]; then
    pass "--output-path redirects review file"
  else
    fail "--output-path did not work (default file present or custom missing)"
  fi
fi

# T8: refuses to run if .reviews/handoff.json is missing
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t8"; mkdir -p "$T/stubs"
  # No handoff.json — should fail fast
  cat > "$T/stubs/opencode" <<'EOF'
#!/usr/bin/env bash
echo "OPENCODE_ARGS:$*" >> "$OPENCODE_STUB_LOG"
EOF
  chmod +x "$T/stubs/opencode"
  rc=0
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider togetherai --reviewer-model X >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$T/stub.log" ]; then
    pass "refuses to run without .reviews/handoff.json (didn't even invoke opencode)"
  else
    fail "ran despite missing handoff.json (rc=$rc, opencode_called=$([ -f "$T/stub.log" ] && echo yes || echo no))"
  fi
fi

# T9: tier shorthand resolves to canonical provider id (e.g., together → togetherai)
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t9"; make_target "$T"
  (cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider together --reviewer-model SomeModel >/dev/null 2>&1) || true
  if [ -f "$T/stub.log" ] && grep -qE "togetherai/SomeModel" "$T/stub.log"; then
    pass "alias 'together' resolves to canonical 'togetherai' in --model arg"
  else
    fail "alias resolution failed"
    cat "$T/stub.log" 2>/dev/null | head -3 >&2 || true
  fi
fi

# T10: --print-prompt emits the review prompt without invoking opencode
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t10"; make_target "$T"
  out="$(cd "$T" && OPENCODE_STUB_LOG="$T/stub.log" PATH="$T/stubs:$PATH" \
    "$SCRIPT" --reviewer-provider togetherai --reviewer-model X --print-prompt 2>&1 || echo SCRIPT_FAILED)"
  if echo "$out" | grep -qE "(handoff|RECHECK|finding)" && [ ! -f "$T/stub.log" ]; then
    pass "--print-prompt emits prompt without invoking opencode"
  else
    fail "--print-prompt either emitted nothing useful or invoked opencode"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All cross-model-review tests passed!"

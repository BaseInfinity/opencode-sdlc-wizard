#!/usr/bin/env bash
# Tests for `npx opencode-sdlc-wizard check` subcommand + the bundled
# scripts/check-updates.sh script that backs it.
#
# The check subcommand answers "is this install behind upstream?" with
# exit code 0 (up-to-date) or 1 (behind) plus a human-readable line.
# Skills + hooks can consume the answer programmatically.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO_ROOT/cli/bin/opencode-sdlc-wizard.js"
SCRIPT="$REPO_ROOT/scripts/check-updates.sh"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/check-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== check subcommand + script ==="

# T1: scripts/check-updates.sh exists + executable
if [ -x "$SCRIPT" ]; then
  pass "scripts/check-updates.sh exists and is executable"
else
  fail "scripts/check-updates.sh missing or not executable"
fi

# T2: bash syntax
if [ -f "$SCRIPT" ] && bash -n "$SCRIPT" 2>/dev/null; then
  pass "check-updates.sh passes bash -n"
else
  fail "check-updates.sh has bash syntax errors"
fi

# T3: --help prints usage
if [ -x "$SCRIPT" ]; then
  out="$("$SCRIPT" --help 2>&1 || echo SCRIPT_FAILED)"
  if echo "$out" | grep -qE "Usage:" && echo "$out" | grep -qiE "stamp|installed|upstream"; then
    pass "check-updates.sh --help mentions stamp/installed/upstream"
  else
    fail "check-updates.sh --help missing stamp/installed/upstream"
  fi
fi

# T4: missing stamp → exit 2 with "no stamp" message
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t4"; mkdir -p "$T"
  rc=0
  out="$(cd "$T" && "$SCRIPT" 2>&1)" || rc=$?
  if [ "$rc" -eq 2 ] && echo "$out" | grep -qiE "no.*stamp|not installed|no \.opencode"; then
    pass "missing stamp → rc=2 with diagnostic message"
  else
    fail "missing stamp: rc=$rc, out: $(echo "$out" | head -1)"
  fi
fi

# T5: stamp at-or-above latest → exit 0
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t5"; mkdir -p "$T/.opencode"
  cat > "$T/.opencode/.wizard-stamp" <<'EOF'
# Managed by opencode-sdlc-wizard. Do not edit by hand.
wizard_version=999.999.999
installed_at=2026-05-04T00:00:00Z
EOF
  rc=0
  out="$(cd "$T" && CHECK_UPDATES_LATEST_OVERRIDE=999.999.999 "$SCRIPT" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE "up.to.date|current"; then
    pass "stamp >= latest → rc=0 with up-to-date message"
  else
    fail "stamp >= latest: rc=$rc, out: $(echo "$out" | head -1)"
  fi
fi

# T6: stamp behind latest → exit 1 with version diff
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t6"; mkdir -p "$T/.opencode"
  cat > "$T/.opencode/.wizard-stamp" <<'EOF'
wizard_version=0.1.0
installed_at=2026-05-04T00:00:00Z
EOF
  rc=0
  out="$(cd "$T" && CHECK_UPDATES_LATEST_OVERRIDE=999.999.999 "$SCRIPT" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] && echo "$out" | grep -qE "0\.1\.0" && echo "$out" | grep -qE "999\.999\.999"; then
    pass "stamp behind latest → rc=1 with installed + latest versions"
  else
    fail "stamp behind: rc=$rc, out: $(echo "$out" | head -2)"
  fi
fi

# T7: --json emits machine-readable output
if [ -x "$SCRIPT" ]; then
  T="$TMP_ROOT/t7"; mkdir -p "$T/.opencode"
  cat > "$T/.opencode/.wizard-stamp" <<'EOF'
wizard_version=0.1.0
EOF
  out="$(cd "$T" && CHECK_UPDATES_LATEST_OVERRIDE=999.999.999 "$SCRIPT" --json 2>&1)" || true
  ok="$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);if(j.installed!=='0.1.0'){console.log('installed-wrong')}else if(j.latest!=='999.999.999'){console.log('latest-wrong')}else if(j.status!=='behind'){console.log('status-wrong')}else{console.log('ok')}}catch(e){console.log('parse-error:'+e.message)}})" 2>/dev/null)"
  if [ "$ok" = "ok" ]; then
    pass "--json emits {installed, latest, status} JSON"
  else
    fail "--json output bad: $ok"
  fi
fi

# T8: CLI passes `check` subcommand through
if [ -x "$CLI" ]; then
  T="$TMP_ROOT/t8"; mkdir -p "$T/.opencode"
  cat > "$T/.opencode/.wizard-stamp" <<'EOF'
wizard_version=999.999.999
EOF
  rc=0
  out="$(cd "$T" && CHECK_UPDATES_LATEST_OVERRIDE=999.999.999 "$CLI" check 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE "up.to.date|current"; then
    pass "CLI 'check' subcommand returns up-to-date when stamp is current"
  else
    fail "CLI check up-to-date path failed: rc=$rc out=$(echo "$out" | head -1)"
  fi
fi

# T9: CLI 'check' supports passthrough flags (--json)
if [ -x "$CLI" ]; then
  T="$TMP_ROOT/t9"; mkdir -p "$T/.opencode"
  cat > "$T/.opencode/.wizard-stamp" <<'EOF'
wizard_version=999.999.999
EOF
  out="$(cd "$T" && CHECK_UPDATES_LATEST_OVERRIDE=999.999.999 "$CLI" check --json 2>&1)" || true
  ok="$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);console.log(j.status==='current'?'ok':'status-wrong:'+j.status)}catch(e){console.log('parse-error:'+e.message)}})" 2>/dev/null)"
  if [ "$ok" = "ok" ]; then
    pass "CLI 'check --json' passes flag through to script"
  else
    fail "CLI check --json: $ok"
  fi
fi

# T10: --help on CLI mentions both init and check
if [ -x "$CLI" ]; then
  out="$("$CLI" --help 2>&1)"
  if echo "$out" | grep -q "init" && echo "$out" | grep -q "check"; then
    pass "CLI --help mentions both init and check subcommands"
  else
    fail "CLI --help missing init or check"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All check-cli tests passed!"

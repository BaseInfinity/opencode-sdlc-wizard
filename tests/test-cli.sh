#!/usr/bin/env bash
# Tests for the npx CLI entry point added in v0.3.0.
#
# Covers:
#   - cli/bin/opencode-sdlc-wizard.js exists, executable, parses
#   - package.json `bin` entry points at the CLI
#   - --help / --version flags work
#   - init subcommand shells out to install.sh and respects --target-dir
#   - npm pack --dry-run includes cli/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO_ROOT/cli/bin/opencode-sdlc-wizard.js"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cli-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== CLI bin entry ==="

# T1: file exists and is executable
if [ -x "$CLI" ]; then
  pass "cli/bin/opencode-sdlc-wizard.js exists and is executable"
else
  fail "cli/bin/opencode-sdlc-wizard.js missing or not executable"
fi

# T2: parses as Node script
if [ -f "$CLI" ] && node --check "$CLI" 2>/dev/null; then
  pass "CLI parses as valid Node script"
else
  fail "CLI has syntax errors (or file missing)"
fi

# T3: package.json declares bin entry
bin_target="$(node -e "console.log((require('$REPO_ROOT/package.json').bin||{})['opencode-sdlc-wizard']||'')" 2>/dev/null || echo '')"
if [ "$bin_target" = "cli/bin/opencode-sdlc-wizard.js" ]; then
  pass "package.json bin.opencode-sdlc-wizard points at cli/bin/opencode-sdlc-wizard.js"
else
  fail "package.json bin entry wrong: '$bin_target' (expected cli/bin/opencode-sdlc-wizard.js)"
fi

# T4: package.json files[] includes cli/
files_arr="$(node -e "console.log((require('$REPO_ROOT/package.json').files||[]).join('|'))" 2>/dev/null || echo '')"
if echo "$files_arr" | tr '|' '\n' | grep -qx 'cli/'; then
  pass "package.json files[] includes cli/"
else
  fail "package.json files[] missing cli/ — npm publish would skip the CLI"
fi

# T5: --help prints usage and exits 0
if [ -x "$CLI" ]; then
  out="$("$CLI" --help 2>&1 || echo CLI_FAILED)"
  if echo "$out" | grep -qE "Usage:" && echo "$out" | grep -q "init"; then
    pass "--help prints usage including 'init' subcommand"
  else
    fail "--help output missing Usage/init: $(echo "$out" | head -3)"
  fi
fi

# T6: --version prints package.json version
if [ -x "$CLI" ]; then
  expected_version="$(node -e "console.log(require('$REPO_ROOT/package.json').version)")"
  out="$("$CLI" --version 2>&1 | tr -d '[:space:]')"
  if [ "$out" = "$expected_version" ]; then
    pass "--version prints package.json version ($expected_version)"
  else
    fail "--version printed '$out', expected '$expected_version'"
  fi
fi

# T7: unknown subcommand exits non-zero
if [ -x "$CLI" ]; then
  rc=0
  "$CLI" totally-bogus-subcommand >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "unknown subcommand rejected (rc=$rc)"
  else
    fail "unknown subcommand silently accepted (should rc!=0)"
  fi
fi

# T8: `init` subcommand shells out to install.sh into --target-dir
if [ -x "$CLI" ]; then
  T="$TMP_ROOT/t8"; mkdir -p "$T"
  if "$CLI" init --target-dir "$T" >/dev/null 2>&1; then
    if [ -f "$T/AGENTS.md" ] && [ -f "$T/.opencode/plugins/sdlc-wizard.js" ] \
       && [ -f "$T/.opencode/scripts/configure-backend.sh" ]; then
      pass "init --target-dir installs the bundle (AGENTS.md + plugin + scripts)"
    else
      fail "init --target-dir ran but bundle incomplete in target"
    fi
  else
    fail "init --target-dir crashed"
  fi
fi

# T9: `init --dry-run` does not write to the target
if [ -x "$CLI" ]; then
  T="$TMP_ROOT/t9"; mkdir -p "$T"
  "$CLI" init --target-dir "$T" --dry-run >/dev/null 2>&1 || true
  if [ ! -f "$T/AGENTS.md" ] && [ ! -d "$T/.opencode" ]; then
    pass "init --dry-run leaves target untouched"
  else
    fail "init --dry-run wrote files to target — dry-run contract broken"
  fi
fi

# T10: npm pack --dry-run output includes cli/bin/opencode-sdlc-wizard.js
pack_listing="$(cd "$REPO_ROOT" && npm pack --dry-run --json 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);const files=j[0]&&j[0].files||[];console.log(files.map(f=>f.path).join('\\n'))}catch(e){console.log('PARSE-ERROR:'+e.message)}})" 2>/dev/null || echo '')"
if echo "$pack_listing" | grep -qx 'cli/bin/opencode-sdlc-wizard.js'; then
  pass "npm pack --dry-run includes cli/bin/opencode-sdlc-wizard.js"
else
  fail "npm pack --dry-run does NOT include cli/bin/opencode-sdlc-wizard.js (publish would ship without CLI)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All CLI tests passed!"

#!/usr/bin/env bash
# Tests for v0.4.0 domain-adaptive TESTING.md templates.
#
# The setup-wizard skill picks one of four domains based on repo signals
# and points the user at the matching TESTING.md template. This test
# proves the templates exist, are appropriately distinct (each mentions
# its domain's testing approach), and ship in the install bundle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates/testing"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dom-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== Domain TESTING.md templates ==="

# T1: 4 templates exist
for d in firmware data-science cli web; do
  if [ -f "$TEMPLATES_DIR/$d.md" ]; then
    pass "templates/testing/$d.md exists"
  else
    fail "templates/testing/$d.md missing"
  fi
done

# T2: each template has domain-appropriate content
declare_assertion() {
  local file="$1"
  local marker="$2"
  local description="$3"
  if [ -f "$file" ] && grep -qiE "$marker" "$file"; then
    pass "$description"
  else
    fail "$description (marker /$marker/ not found in $(basename "$file"))"
  fi
}

declare_assertion "$TEMPLATES_DIR/firmware.md" "HIL|hardware.in.loop|device|embedded|flash|JTAG" \
  "firmware.md mentions hardware-in-loop / embedded / device terminology"
declare_assertion "$TEMPLATES_DIR/data-science.md" "notebook|model.eval|dataset|fixture|jupyter|reproduc" \
  "data-science.md mentions notebooks / model eval / datasets"
declare_assertion "$TEMPLATES_DIR/cli.md" "argv|argument|flag|stdin|stdout|exit.code|behavior contract" \
  "cli.md mentions argv / flags / stdin / exit codes / behavior contract"
declare_assertion "$TEMPLATES_DIR/web.md" "API|integration|endpoint|HTTP|fixture|Playwright|E2E" \
  "web.md mentions API / endpoints / HTTP / E2E"

# T3: each template has the standard testing-diamond structure (some layered approach)
for d in firmware data-science cli web; do
  if [ -f "$TEMPLATES_DIR/$d.md" ]; then
    if grep -qiE "layer|tier|pyramid|diamond|level" "$TEMPLATES_DIR/$d.md"; then
      pass "$d.md describes layered testing structure"
    else
      fail "$d.md missing layered testing structure"
    fi
  fi
done

# T4: install.sh REQUIRED_SOURCES includes all 4 templates (so they ship)
for d in firmware data-science cli web; do
  if grep -q "templates/testing/$d.md" "$REPO_ROOT/install.sh"; then
    pass "install.sh REQUIRED_SOURCES includes templates/testing/$d.md"
  else
    fail "install.sh does not list templates/testing/$d.md — bundle won't ship it"
  fi
done

# T5: install delivers templates to .opencode/templates/testing/ in target
target="$(mktemp -d "$TMP_ROOT/install.XXXXXX")"
bash "$REPO_ROOT/install.sh" --target-dir "$target" >/dev/null 2>&1 || true
for d in firmware data-science cli web; do
  if [ -f "$target/.opencode/templates/testing/$d.md" ]; then
    pass "install delivers .opencode/templates/testing/$d.md"
  else
    fail "install did NOT deliver .opencode/templates/testing/$d.md"
  fi
done

# T6: setup-wizard SKILL.md mentions all 4 domains + references templates
SKILL="$REPO_ROOT/skills/setup-wizard/SKILL.md"
for d in firmware data-science cli web; do
  if grep -qiE "\b$d\b" "$SKILL"; then
    pass "setup-wizard skill mentions '$d' domain"
  else
    fail "setup-wizard skill does not mention '$d' domain"
  fi
done
if grep -qE "templates/testing|\.opencode/templates/testing" "$SKILL"; then
  pass "setup-wizard skill references the templates directory"
else
  fail "setup-wizard skill missing reference to templates/testing/"
fi

# T7: package.json files[] includes templates/
files_arr="$(node -e "console.log((require('$REPO_ROOT/package.json').files||[]).join('|'))" 2>/dev/null || echo '')"
if echo "$files_arr" | tr '|' '\n' | grep -qx 'templates/'; then
  pass "package.json files[] includes templates/"
else
  fail "package.json files[] missing templates/ — npm publish would skip them"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All domain template tests passed!"

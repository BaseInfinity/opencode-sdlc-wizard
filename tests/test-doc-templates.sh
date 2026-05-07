#!/usr/bin/env bash
# Tests for v0.6.0 — SDLC.md + ARCHITECTURE.md templates.
#
# Setup-wizard skill generates SDLC.md, TESTING.md, ARCHITECTURE.md as
# part of project bootstrap. v0.4.0 added domain templates for TESTING.md
# (4 of them). v0.6.0 closes the gap by adding SDLC.md + ARCHITECTURE.md
# templates so the skill has something to copy from.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/doc-tmpl-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== SDLC.md + ARCHITECTURE.md templates ==="

# T1-T2: templates exist
for d in sdlc architecture; do
  if [ -f "$REPO_ROOT/templates/$d.md" ]; then
    pass "templates/$d.md exists"
  else
    fail "templates/$d.md missing"
  fi
done

# T3: SDLC.md template has the load-bearing sections
SDLC_TPL="$REPO_ROOT/templates/sdlc.md"
for marker in "Plan" "TDD" "self-review" "Confidence" "wizard.version|wizard.Version|SDLC.Wizard.Version"; do
  if [ -f "$SDLC_TPL" ] && grep -qiE "$marker" "$SDLC_TPL"; then
    pass "sdlc.md mentions /$marker/"
  else
    fail "sdlc.md missing /$marker/"
  fi
done

# T4: SDLC.md references invocations of the actual skills
if [ -f "$SDLC_TPL" ]; then
  if grep -qE 'skill\(\{[[:space:]]*name:[[:space:]]*"sdlc"' "$SDLC_TPL"; then
    pass "sdlc.md tells users to invoke skill({ name: \"sdlc\" })"
  else
    fail "sdlc.md does not invoke the sdlc skill"
  fi
fi

# T5: ARCHITECTURE.md template has the load-bearing sections
ARCH_TPL="$REPO_ROOT/templates/architecture.md"
for marker in "overview|System overview|Components" "Environments|Deployment" "decisions|trade.offs|Decision"; do
  if [ -f "$ARCH_TPL" ] && grep -qiE "$marker" "$ARCH_TPL"; then
    pass "architecture.md mentions /$marker/"
  else
    fail "architecture.md missing /$marker/"
  fi
done

# T6: install.sh REQUIRED_SOURCES + declare_target include both
for d in sdlc architecture; do
  if grep -q "templates/$d.md" "$REPO_ROOT/install.sh"; then
    pass "install.sh REQUIRED_SOURCES includes templates/$d.md"
  else
    fail "install.sh does not list templates/$d.md"
  fi
done

# T7: install delivers them to .opencode/templates/
target="$(mktemp -d "$TMP_ROOT/install.XXXXXX")"
bash "$REPO_ROOT/install.sh" --target-dir "$target" >/dev/null 2>&1 || true
for d in sdlc architecture; do
  if [ -f "$target/.opencode/templates/$d.md" ]; then
    pass "install delivers .opencode/templates/$d.md"
  else
    fail "install did NOT deliver .opencode/templates/$d.md"
  fi
done

# T8: setup-wizard skill references SDLC.md + ARCHITECTURE.md template paths
SKILL="$REPO_ROOT/skills/setup-wizard/SKILL.md"
for d in sdlc architecture; do
  if grep -qE "templates/$d\.md|templates/testing/${d}\.md" "$SKILL"; then
    pass "setup-wizard skill references templates/$d.md"
  else
    fail "setup-wizard skill missing templates/$d.md reference"
  fi
done

# T18-T22: docs/cost-ladder.md (v0.8.0)
COST_LADDER="$REPO_ROOT/docs/cost-ladder.md"

if [ -f "$COST_LADDER" ]; then
  pass "docs/cost-ladder.md exists"
else
  fail "docs/cost-ladder.md missing"
fi

# Load-bearing sections — the doc's whole point is the three budget tiers
for marker in '\$0/mo' '\$20/mo' '\$200/mo' "capability floor" "hybrid"; do
  if [ -f "$COST_LADDER" ] && grep -qiE "$marker" "$COST_LADDER"; then
    pass "cost-ladder.md mentions /$marker/"
  else
    fail "cost-ladder.md missing /$marker/"
  fi
done

# package.json files[] must include docs/ so npm publish ships the cost ladder
if grep -qE '"docs/"' "$REPO_ROOT/package.json"; then
  pass "package.json files[] includes docs/ (cost-ladder.md will publish)"
else
  fail "package.json files[] missing docs/"
fi

# v0.8.6 — setup-wizard SKILL.md must reference every backend provider the
# v0.8.x picker emits, and the --free-tier-first flag. Drift here gives users
# a stale tier list when they run the skill (caught alongside the install.sh
# next-steps drift in v0.8.4 — same root cause, different surface).
SETUP="$REPO_ROOT/skills/setup-wizard/SKILL.md"
missing=""
for token in cerebras deepseek nvidia_nim google_aistudio mlx "--free-tier-first"; do
  if ! grep -qi -- "$token" "$SETUP"; then
    missing="$missing $token"
  fi
done
if [ -z "$missing" ]; then
  pass "setup-wizard SKILL.md mentions every v0.8.x provider + --free-tier-first"
else
  fail "setup-wizard SKILL.md missing tokens:$missing"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All doc template tests passed!"

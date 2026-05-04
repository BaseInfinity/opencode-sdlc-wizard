#!/usr/bin/env bash
# Install behavior tests — proves install.sh is non-destructive and idempotent.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

mk_target() { mktemp -d -t opencode-sdlc-test.XXXXXX; }

echo "=== install.sh behavior ==="

# 1. Fresh-install: empty target → all files installed
target="$(mk_target)"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1 || echo "INSTALLER_FAILED")"
if echo "$out" | grep -q "INSTALLER_FAILED"; then
    fail "fresh install crashed"
else
    if [ -f "$target/AGENTS.md" ] && \
       [ -f "$target/.opencode/plugins/sdlc-wizard.js" ] && \
       [ -f "$target/.opencode/hooks/tdd-pretool-check.sh" ] && \
       [ -f "$target/.opencode/skills/sdlc/SKILL.md" ]; then
        pass "fresh install: AGENTS.md + plugin + hook + skill all present in target"
    else
        fail "fresh install: missing one or more required files in target"
    fi
    if [ -x "$target/.opencode/hooks/tdd-pretool-check.sh" ]; then
        pass "fresh install: hook scripts are executable"
    else
        fail "fresh install: hook scripts not executable"
    fi
    if [ -f "$target/.opencode/.wizard-stamp" ]; then
        pass "fresh install: wizard stamp written"
    else
        fail "fresh install: wizard stamp missing"
    fi
fi
rm -rf "$target"

# 2. Re-install on already-installed target: idempotent (all files MATCH)
target="$(mk_target)"
bash "$INSTALLER" --target-dir "$target" >/dev/null
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
match_count=$(echo "$out" | grep -cE "  MATCH " || true)
installed_count=$(echo "$out" | grep -cE "  INSTALLED " || true)
if [ "$match_count" -ge 12 ] && [ "$installed_count" -eq 0 ]; then
    pass "re-install is idempotent (all files MATCH on second run)"
else
    fail "re-install not idempotent: $installed_count installed, $match_count matched"
fi
rm -rf "$target"

# 3. Customized file → preserved without --force
target="$(mk_target)"
bash "$INSTALLER" --target-dir "$target" >/dev/null
echo "# user customization" >> "$target/AGENTS.md"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
if echo "$out" | grep -q "CUSTOMIZED  AGENTS.md"; then
    pass "customized AGENTS.md flagged as CUSTOMIZED, not overwritten"
else
    fail "customized AGENTS.md not detected"
fi
if grep -q "user customization" "$target/AGENTS.md"; then
    pass "customized AGENTS.md content preserved"
else
    fail "customized AGENTS.md content lost (overwritten)"
fi
rm -rf "$target"

# 4. --force overwrites customizations (and only with --force)
target="$(mk_target)"
bash "$INSTALLER" --target-dir "$target" >/dev/null
echo "# user customization" >> "$target/AGENTS.md"
bash "$INSTALLER" --target-dir "$target" --force >/dev/null
if ! grep -q "user customization" "$target/AGENTS.md"; then
    pass "--force overwrites customizations"
else
    fail "--force failed to overwrite customizations"
fi
rm -rf "$target"

# 5. Skills install at .opencode/skills/ (not skills/) — OpenCode-native location
target="$(mk_target)"
bash "$INSTALLER" --target-dir "$target" >/dev/null
if [ -f "$target/.opencode/skills/sdlc/SKILL.md" ] && [ ! -f "$target/skills/sdlc/SKILL.md" ]; then
    pass "skills installed at .opencode/skills/ (OpenCode-native), not skills/"
else
    fail "skills installed in wrong location"
fi
rm -rf "$target"

# 6. Existing opencode.json untouched (we don't try to merge it in v0.1.0)
target="$(mk_target)"
echo '{"model": "anthropic/claude-opus-4-7"}' > "$target/opencode.json"
bash "$INSTALLER" --target-dir "$target" >/dev/null
if [ "$(cat "$target/opencode.json")" = '{"model": "anthropic/claude-opus-4-7"}' ]; then
    pass "existing opencode.json untouched"
else
    fail "existing opencode.json was modified (should be untouched in v0.1.0)"
fi
rm -rf "$target"

# 7. Help flag works
if "$INSTALLER" --help 2>&1 | grep -q "Non-destructive merge"; then
    pass "--help prints usage"
else
    fail "--help broken"
fi

# 8. Invalid arg fails fast
if ! bash "$INSTALLER" --bogus-flag 2>/dev/null; then
    pass "invalid flag rejected"
else
    fail "invalid flag silently accepted"
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All install behavior tests passed!"

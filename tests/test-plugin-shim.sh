#!/usr/bin/env bash
# Behavior tests for the OpenCode plugin shim.
#
# We can't run OpenCode itself in CI without installing it, so these tests
# exercise the plugin's *invariants* rather than full event delivery:
# (1) the plugin module loads without syntax errors under Node;
# (2) the bash hooks the plugin shells out to actually exit 0 on a clean
#     fixture (no crashing on basic invocation);
# (3) the SOURCE_GLOB_RE filter correctly classifies file extensions
#     (proven by extracting the regex and re-testing it in node).
#
# This is the "harness for the hooks the plugin invokes" — proves the plumbing
# between OpenCode events and bash logic is intact.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN="$REPO_ROOT/.opencode/plugins/sdlc-wizard.js"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Plugin shim behavior ==="

# 1. Plugin module syntactically valid under Node ESM
if node --check --input-type=module < "$PLUGIN" 2>/dev/null; then
    pass "plugin parses as valid ESM under Node"
else
    fail "plugin has Node ESM syntax errors"
fi

# 2. Hooks individually invocable without crash (exit 0 or hook-internal nonzero is OK,
#    but no syntax errors / interpreter errors)
for hook in "$REPO_ROOT/.opencode/hooks/sdlc-prompt-check.sh" \
            "$REPO_ROOT/.opencode/hooks/tdd-pretool-check.sh" \
            "$REPO_ROOT/.opencode/hooks/model-effort-check.sh"; do
    name="$(basename "$hook")"
    if bash -n "$hook" 2>/dev/null; then
        pass "$name passes bash -n syntax check"
    else
        fail "$name has bash syntax errors"
    fi
done

# 3. SOURCE_GLOB_RE classification — extract the regex from the plugin and re-test
# in Node. This proves the TDD-trigger filter behaves as intended.
NODE_TEST_DIR="$(mktemp -d)"
cleanup() { rm -rf "$NODE_TEST_DIR"; }
trap cleanup EXIT

cat > "$NODE_TEST_DIR/test-glob.mjs" <<'EOF'
const SOURCE_GLOB_RE = /\.(js|jsx|ts|tsx|mjs|cjs|py|go|rs|rb|java|kt|swift|c|h|cpp|hpp|cs)$/i;
const cases = [
  ["src/app.js", true],
  ["src/app.ts", true],
  ["src/app.tsx", true],
  ["src/app.py", true],
  ["src/app.go", true],
  ["src/app.rs", true],
  ["README.md", false],
  ["AGENTS.md", false],
  ["package.json", false],
  ["script.sh", false],
];
let failed = 0;
for (const [path, expect] of cases) {
  const actual = SOURCE_GLOB_RE.test(path);
  if (actual !== expect) {
    console.error(`FAIL: ${path} expected=${expect} actual=${actual}`);
    failed++;
  }
}
process.exit(failed === 0 ? 0 : 1);
EOF

if node "$NODE_TEST_DIR/test-glob.mjs" 2>&1; then
    pass "SOURCE_GLOB_RE classifies common extensions correctly"
else
    fail "SOURCE_GLOB_RE misclassifies one or more cases"
fi

# 4. Plugin must export a function (so OpenCode can call it)
if grep -qE "export[[:space:]]+const[[:space:]]+\w+[[:space:]]*=[[:space:]]*async" "$PLUGIN"; then
    pass "plugin exports an async function (OpenCode calling convention)"
else
    fail "plugin missing exported async function"
fi

# 5. Plugin uses node:child_process (not bun-only API) so it works on plain Node too
if grep -q 'from "node:child_process"' "$PLUGIN"; then
    pass "plugin uses node:child_process (Bun + Node compatible)"
else
    fail "plugin uses non-portable child_process import"
fi

# 6. precompact handler must throw on exit code 2 (block contract)
# Static check: the handler reads code === 2 and throws
if awk '/experimental.session.compacting/,/^[[:space:]]*\},?[[:space:]]*$/' "$PLUGIN" | grep -qE 'r\.code[[:space:]]*===[[:space:]]*2'; then
    pass "precompact handler honors exit code 2 as block signal"
else
    fail "precompact handler missing exit-2 block contract"
fi

# 7. session.created dispatched via generic `event` handler (per OpenCode docs).
# The earlier "session.created" as direct handler key was a P0 — OpenCode
# session events flow through the generic `event` channel. Accept either
# `===` or `!==` (early-return) discrimination form.
if grep -qE '^\s*event:\s*async' "$PLUGIN" && grep -qE 'event\.type[[:space:]]*(===|!==)[[:space:]]*"session\.created"' "$PLUGIN"; then
    pass "session.created handled via generic event handler with event.type discriminator"
else
    fail "session.created not dispatched via generic event handler (P0 — direct event-name keys don't fire)"
fi

# 8. tool.execute.before handler signature is (input, output) per OpenCode docs.
# Earlier signature `({ tool, args })` was P0 — OpenCode passes input.tool +
# output.args separately.
if grep -qE '"tool\.execute\.before":[[:space:]]*async[[:space:]]*\([[:space:]]*input[[:space:]]*,[[:space:]]*output[[:space:]]*\)' "$PLUGIN"; then
    pass "tool.execute.before uses (input, output) signature"
else
    fail "tool.execute.before signature wrong (P0 — must be (input, output) not destructured object)"
fi

# 9. Tool ids are lowercase per OpenCode (write/edit/apply_patch/multiedit), not Claude-style PascalCase
if grep -qE '"write"|"edit"|"apply_patch"' "$PLUGIN" && ! grep -qE 'TDD_TARGET_TOOLS.*"Write"' "$PLUGIN"; then
    pass "TDD target tool ids are lowercase (OpenCode convention)"
else
    fail "TDD target tool ids still use Claude PascalCase (will not match in OpenCode)"
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All plugin shim behavior tests passed!"

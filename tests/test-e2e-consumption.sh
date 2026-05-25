#!/usr/bin/env bash
# E2E consumption smoke test (v0.13.3).
#
# Different from the 12 fast unit suites in npm test — those test scripts
# in isolation against the SOURCE layout. This one packs the current repo
# as if for publish, installs it into a fresh tmp dir as a real consumer
# would, then runs `pick --dry-run` against EVERY tier/provider combo
# to validate the published bundle end-to-end.
#
# Catches regressions that source-layout tests miss:
#   - install.sh fails to deliver some script to .opencode/scripts/
#   - pick-backend.sh's PATH-first sibling-lookup breaks under the
#     installed layout
#   - A default-model entry for a tier is silently missing
#   - The JSON emitted by configure-backend.sh is structurally invalid
#   - package.json files[] excluded something the installer needs
#
# Not in the default `npm test` chain because it takes 30-60 seconds
# (npm pack + install) — invoke explicitly:
#   npm run test:e2e
# Or against the LIVE published latest instead of the local pack:
#   E2E_SOURCE=npm-latest bash tests/test-e2e-consumption.sh
#
# Exit codes: 0 all tier/provider combos OK; 1 any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/e2e-consumption.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "=== v0.13.3 E2E consumption smoke ==="

# Resolve the wizard source for this run. Default: pack the local repo
# so we test exactly what would publish. Override via E2E_SOURCE=npm-latest
# to test the live npm latest instead.
TARGET_DIR="$TMP_ROOT/consumer"
mkdir -p "$TARGET_DIR"

case "${E2E_SOURCE:-local-pack}" in
  npm-latest)
    SOURCE_DESC="published npm latest"
    INSTALL_INVOCATION=(npx -y opencode-sdlc-wizard@latest init --force --target-dir "$TARGET_DIR")
    ;;
  local-pack|*)
    SOURCE_DESC="local pack of $(node -p "require('$REPO_ROOT/package.json').version")"
    cd "$REPO_ROOT"
    TARBALL="$(npm pack --pack-destination "$TMP_ROOT" 2>/dev/null | tail -1)"
    if [ -z "$TARBALL" ] || [ ! -f "$TMP_ROOT/$TARBALL" ]; then
      fail "npm pack did not produce a tarball"
      exit 1
    fi
    # Use --package= form: `npx <path>` tries to execute the tarball as a
    # script (sh: permission denied); --package= tells npx to install it
    # and then run the binary by name. Mirrors how `npx <pkg@version>` works.
    INSTALL_INVOCATION=(npx -y --package="$TMP_ROOT/$TARBALL" opencode-sdlc-wizard init --force --target-dir "$TARGET_DIR")
    ;;
esac

echo "Source: $SOURCE_DESC"
echo "Target: $TARGET_DIR"
echo ""

# T1: install delivers the bundle
echo "--- T1: install delivers bundle to .opencode/ ---"
"${INSTALL_INVOCATION[@]}" >/dev/null 2>&1 || true
if [ -f "$TARGET_DIR/.opencode/scripts/pick-backend.sh" ] \
   && [ -f "$TARGET_DIR/.opencode/scripts/configure-backend.sh" ] \
   && [ -f "$TARGET_DIR/.opencode/scripts/detect-backends.sh" ] \
   && [ -f "$TARGET_DIR/.opencode/.wizard-stamp" ]; then
  pass "install delivers pick-backend.sh + configure-backend.sh + detect-backends.sh + .wizard-stamp"
else
  fail "install did NOT deliver expected files"
  ls "$TARGET_DIR/.opencode/scripts/" 2>&1 | head -10
  exit 1
fi

# T2: stamp matches package.json
EXPECTED_VERSION="$(node -p "require('$REPO_ROOT/package.json').version")"
STAMPED_VERSION="$(grep wizard_version "$TARGET_DIR/.opencode/.wizard-stamp" | cut -d= -f2)"
if [ "$STAMPED_VERSION" = "$EXPECTED_VERSION" ] || [ "${E2E_SOURCE:-local-pack}" = "npm-latest" ]; then
  pass "wizard_version stamp = $STAMPED_VERSION"
else
  fail "stamped $STAMPED_VERSION ≠ expected $EXPECTED_VERSION"
fi

# T3–T11: pick every tier/provider combo, validate the emitted JSON
echo ""
echo "--- T3+: dry-run pick across all 6 tiers ---"
PICK="$TARGET_DIR/.opencode/scripts/pick-backend.sh"

# Each entry: tier:provider:expected_provider_block_key
# expected_provider_block_key is "" for subscription tiers (empty provider: {})
COMBOS=(
  "private_local:ollama:ollama"
  "enterprise:azure_openai:azure"
  "hosted_oss:cerebras:cerebras"
  "managed:opencode:opencode"
  "proprietary:anthropic:anthropic"
  "proprietary:zai:zai"
  "subscription:copilot:"
  "subscription:chatgpt:"
  "subscription:grok:"
)

for combo in "${COMBOS[@]}"; do
  IFS=":" read -r tier prov expected_pkey <<<"$combo"
  # --target-dir explicit so we never accidentally test against the
  # caller's actual opencode.json (would trip no-clobber pre-v0.13.3)
  json="$(env ANTHROPIC_API_KEY=x OPENAI_API_KEY=x CEREBRAS_API_KEY=x \
             OPENCODE_ZEN_API_KEY=x ZAI_API_KEY=x AZURE_RESOURCE_NAME=x \
             "$PICK" --dry-run --target-dir "$TARGET_DIR" \
                     --tier "$tier" --provider "$prov" 2>&1 \
           | sed -n '/^{/,$p')"
  result="$(printf '%s' "$json" | python3 -c "
import sys, json
try:
    j = json.load(sys.stdin)
    assert 'model' in j, 'missing model'
    assert '/' in j['model'], 'model not in provider/model form: ' + j['model']
    assert 'provider' in j, 'missing provider key'
    # Subscription tiers have empty provider block; others must have one entry.
    if '$expected_pkey' == '':
        assert j['provider'] == {} or list(j['provider'].keys()) == [], \
            'subscription tier should have empty provider, got: ' + str(j['provider'])
    else:
        assert '$expected_pkey' in j['provider'], \
            'expected provider.$expected_pkey, got: ' + str(list(j['provider'].keys()))
    print('OK ' + j['model'])
except Exception as e:
    print('FAIL ' + str(e))
" 2>&1)"
  if [[ "$result" == OK* ]]; then
    pass "$tier/$prov → ${result#OK }"
  else
    fail "$tier/$prov: $result"
  fi
done

# T12: full hybrid stack (model + small_model + 4 agent blocks + 4 sandboxes
#      + 4 temps) writes structurally valid JSON
echo ""
echo "--- T12: full v0.13.x hybrid (every flag in one call) ---"
hybrid_json="$(env ANTHROPIC_API_KEY=x OPENAI_API_KEY=x CEREBRAS_API_KEY=x GROQ_API_KEY=x \
                  "$PICK" --dry-run --target-dir "$TARGET_DIR" \
                  --tier proprietary --provider anthropic \
                  --small-tier proprietary --small-provider anthropic --small-model claude-haiku-4-5 \
                  --planner-tier hosted_oss --planner-provider groq --planner-temp 0.1 \
                  --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-temp 0.1 \
                  --security-tier proprietary --security-provider openai --security-temp 0.1 \
                  --sandbox-plan --sandbox-security --sandbox-test-writer --sandbox-docs \
                  --coder-temp 0.3 2>&1 | sed -n '/^{/,$p')"
result="$(printf '%s' "$hybrid_json" | python3 -c "
import sys, json
try:
    j = json.load(sys.stdin)
    assert j['model'] == 'anthropic/claude-opus-4-7', 'coder model: ' + j['model']
    assert j['small_model'] == 'anthropic/claude-haiku-4-5', 'small_model: ' + j.get('small_model','MISSING')
    agents = j.get('agent', {})
    for required in ['build', 'plan', 'review', 'security', 'test-writer', 'docs']:
        assert required in agents, 'missing agent.' + required
    assert agents['build']['temperature'] == 0.3
    assert agents['plan']['temperature'] == 0.1
    assert agents['plan']['model'] == 'groq/gpt-oss-120b'
    assert agents['plan']['tools']['write'] is False
    assert agents['review']['model'] == 'cerebras/gpt-oss-120b'
    assert agents['security']['tools']['write'] is False
    assert agents['test-writer']['permission']['write']['**/*.test.*'] == 'allow'
    assert agents['docs']['permission']['write']['**/*.md'] == 'allow'
    print('OK ' + str(len(agents)) + ' agents, ' + str(len(j['provider'])) + ' providers')
except Exception as e:
    print('FAIL ' + str(e))
" 2>&1)"
if [[ "$result" == OK* ]]; then
  pass "full hybrid: ${result#OK }"
else
  fail "full hybrid: $result"
fi

# T13: opencode CLI (if available) validates the merged config
echo ""
echo "--- T13: opencode debug config (optional — runs only if CLI present) ---"
if command -v opencode >/dev/null 2>&1; then
  opencode_version="$(opencode --version 2>&1 | head -1 || echo unknown)"
  echo "  opencode CLI: $opencode_version"
  # Write a real opencode.json from a simple pick + try to debug-load it
  CONFIG_DIR="$TMP_ROOT/cfg-check"; mkdir -p "$CONFIG_DIR"
  env ANTHROPIC_API_KEY=x "$PICK" --tier proprietary --provider anthropic \
                                  --target-dir "$CONFIG_DIR" --force >/dev/null 2>&1
  if [ -f "$CONFIG_DIR/opencode.json" ]; then
    # opencode debug config may not exist in older versions or may require
    # a working session — best-effort: just JSON-parse the file via node
    # (proves the file is well-formed; the deeper opencode validation is
    # left to actual consumption).
    if node -e "JSON.parse(require('fs').readFileSync('$CONFIG_DIR/opencode.json','utf8'))" 2>/dev/null; then
      pass "emitted opencode.json parses cleanly with node (opencode debug not run — see consumption)"
    else
      fail "emitted opencode.json is not valid JSON"
    fi
  else
    fail "configure-backend did not write opencode.json to target-dir"
  fi
else
  echo "  (opencode CLI not on PATH — skipping; consumption test only)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All E2E consumption tests passed!"

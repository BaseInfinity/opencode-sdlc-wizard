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
       [ -f "$target/PRIVACY.md" ] && \
       [ -f "$target/.opencode/plugins/sdlc-wizard.js" ] && \
       [ -f "$target/.opencode/hooks/tdd-pretool-check.sh" ] && \
       [ -f "$target/.opencode/scripts/detect-backends.sh" ] && \
       [ -f "$target/.opencode/scripts/configure-backend.sh" ] && \
       [ -f "$target/.opencode/skills/sdlc/SKILL.md" ]; then
        pass "fresh install: AGENTS.md + PRIVACY.md + plugin + hook + scripts + skill all present in target"
    else
        fail "fresh install: missing one or more required files in target"
    fi
    if [ -x "$target/.opencode/hooks/tdd-pretool-check.sh" ]; then
        pass "fresh install: hook scripts are executable"
    else
        fail "fresh install: hook scripts not executable"
    fi
    if [ -x "$target/.opencode/scripts/detect-backends.sh" ] && \
       [ -x "$target/.opencode/scripts/configure-backend.sh" ]; then
        pass "fresh install: backend picker scripts are executable"
    else
        fail "fresh install: backend picker scripts not executable"
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
# v0.2.0 bundle: 16 sources (1 AGENTS.md + 1 PRIVACY.md + 6 hooks + 1 plugin + 2 scripts + 4 skills + 1 hook helper)
if [ "$match_count" -ge 15 ] && [ "$installed_count" -eq 0 ]; then
    pass "re-install is idempotent (all files MATCH on second run)"
else
    fail "re-install not idempotent: $installed_count installed, $match_count matched"
fi
# Stamp idempotency: installed_at field must be preserved across no-op re-runs
stamp1=$(grep "^installed_at=" "$target/.opencode/.wizard-stamp")
sleep 1
bash "$INSTALLER" --target-dir "$target" >/dev/null
stamp2=$(grep "^installed_at=" "$target/.opencode/.wizard-stamp")
if [ "$stamp1" = "$stamp2" ]; then
    pass "wizard-stamp installed_at preserved across no-op re-run (true idempotency)"
else
    fail "wizard-stamp installed_at changed on no-op re-run: '$stamp1' → '$stamp2'"
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

# 6. Existing opencode.json untouched by install.sh (backend picker is a
#    separate explicit step run from the setup-wizard skill, not auto-run
#    on install — this contract is preserved through v0.2.0)
target="$(mk_target)"
echo '{"model": "anthropic/claude-opus-4-7"}' > "$target/opencode.json"
bash "$INSTALLER" --target-dir "$target" >/dev/null
if [ "$(cat "$target/opencode.json")" = '{"model": "anthropic/claude-opus-4-7"}' ]; then
    pass "existing opencode.json untouched by install.sh"
else
    fail "existing opencode.json was modified by install.sh (configure-backend.sh is a separate opt-in)"
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

# 9. Next-steps hint stays current with the picker — must list every provider
#    detect-backends.sh emits, plus --free-tier-first flag and cost-ladder ref.
#    Project-tracker consumption test (2026-05-25, v0.13.4 finding) caught
#    the v0.10.x list still being printed after v0.11/v0.12/v0.13 added
#    zai, managed/opencode, and the entire subscription tier (Copilot,
#    ChatGPT, Grok). Same drift pattern as the v0.8.0→v0.8.4 finding.
target="$(mk_target)"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
missing=""
for token in \
    "ollama" "lm_studio" "llama.cpp" "vllm" "mlx" \
    "azure" "bedrock" \
    "together" "groq" "openrouter" "cerebras" "deepseek" "nvidia" \
    "anthropic" "openai" "google" "zai" \
    "managed" "opencode" \
    "subscription" "github-copilot" "chatgpt" "grok" \
    "pick" \
    "--free-tier-first" \
    "cost-ladder.md"; do
    if ! echo "$out" | grep -qi -- "$token"; then
        missing="$missing $token"
    fi
done
if [ -z "$missing" ]; then
    pass "next-steps hint mentions all 6 tiers + all providers + pick subcommand + flag + cost-ladder"
else
    fail "next-steps hint missing tokens:$missing"
fi
rm -rf "$target"

# 10. Dual-stack awareness — when a sibling SDLC wizard (claude-sdlc-wizard
#     via .claude/skills/sdlc, or codex-sdlc-wizard via .codex/) is already
#     installed, install.sh prints a heads-up that opencode-sdlc-wizard sits
#     alongside it. v0.8.6 finding from the states-project-research
#     consumption test — wizard didn't notice the repo already had a
#     claude-sdlc-wizard install.
target="$(mk_target)"
mkdir -p "$target/.claude/skills/sdlc"
echo "stub" > "$target/.claude/skills/sdlc/SKILL.md"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
if echo "$out" | grep -qi "claude-sdlc-wizard"; then
    pass "install detects existing claude-sdlc-wizard and prints heads-up"
else
    fail "install missed claude-sdlc-wizard sibling install"
fi
rm -rf "$target"

# 11. Codex sibling detection (.codex/ directory)
target="$(mk_target)"
mkdir -p "$target/.codex"
echo "stub" > "$target/.codex/config.toml"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
if echo "$out" | grep -qi "codex-sdlc-wizard"; then
    pass "install detects existing codex-sdlc-wizard and prints heads-up"
else
    fail "install missed codex-sdlc-wizard sibling install"
fi
rm -rf "$target"

# 12. No false positive — fresh empty target gets no sibling-detected message
target="$(mk_target)"
out="$(bash "$INSTALLER" --target-dir "$target" 2>&1)"
if echo "$out" | grep -qiE "claude-sdlc-wizard|codex-sdlc-wizard"; then
    fail "false-positive sibling detection on empty target"
else
    pass "fresh target — no false sibling-wizard detection"
fi
rm -rf "$target"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All install behavior tests passed!"

#!/usr/bin/env bash
# Bundle integrity tests — every required file ships in the right place.
# These are existence tests because they prove the bundle is shippable.
# Behavior tests live in test-plugin-shim.sh and test-install.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Bundle integrity ==="

# 5 hooks at top-level and dogfood location
for hook in _find-sdlc-root.sh sdlc-prompt-check.sh tdd-pretool-check.sh \
            instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh; do
    if [ -f "$REPO_ROOT/hooks/$hook" ]; then
        pass "hooks/$hook exists at top-level"
    else
        fail "hooks/$hook missing at top-level"
    fi
    if [ -f "$REPO_ROOT/.opencode/hooks/$hook" ]; then
        pass ".opencode/hooks/$hook exists (dogfood location)"
    else
        fail ".opencode/hooks/$hook missing (dogfood location)"
    fi
done

# Hooks must match between top-level and .opencode/ (single source of truth)
for hook in sdlc-prompt-check.sh tdd-pretool-check.sh \
            instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh; do
    if cmp -s "$REPO_ROOT/hooks/$hook" "$REPO_ROOT/.opencode/hooks/$hook"; then
        pass "hooks/$hook == .opencode/hooks/$hook (no drift)"
    else
        fail "hooks/$hook differs from .opencode/hooks/$hook (drift bug)"
    fi
done

# Plugin shim
if [ -f "$REPO_ROOT/.opencode/plugins/sdlc-wizard.js" ]; then
    pass ".opencode/plugins/sdlc-wizard.js exists"
else
    fail ".opencode/plugins/sdlc-wizard.js missing"
fi

# 5 skills (setup/update use the -wizard suffix; cross-model-review
# added in v0.3.1 alongside the OSS-reviewer alternative)
for sk in sdlc setup-wizard update-wizard feedback cross-model-review; do
    if [ -f "$REPO_ROOT/skills/$sk/SKILL.md" ]; then
        pass "skills/$sk/SKILL.md exists"
    else
        fail "skills/$sk/SKILL.md missing"
    fi
done

# Skill frontmatter `name` MUST match directory name (OpenCode discovery rule)
for sk in sdlc setup-wizard update-wizard feedback cross-model-review; do
    actual_name=$(awk '/^name:/ {print $2; exit}' "$REPO_ROOT/skills/$sk/SKILL.md" 2>/dev/null)
    if [ "$actual_name" = "$sk" ]; then
        pass "skills/$sk/SKILL.md frontmatter name matches directory ($sk)"
    else
        fail "skills/$sk/SKILL.md frontmatter name='$actual_name' but dir='$sk' (OpenCode discovery requires match)"
    fi
done

# Skills must NOT contain stale Claude-only references after the OpenCode adaptation
# (the helper-skills audit in v0.1.0 rewrote setup-wizard/update-wizard/feedback to
# OpenCode-native; sdlc still references Claude tooling because it's mostly cross-agent
# workflow guidance, but it should not invoke Claude-only commands as required)
for stale in "CLAUDE_CODE_SDLC_WIZARD" "agentic-sdlc-wizard" "claude-sdlc-wizard"; do
    found=$(grep -lr "$stale" "$REPO_ROOT/skills/setup-wizard/" "$REPO_ROOT/skills/update-wizard/" "$REPO_ROOT/skills/feedback/" 2>/dev/null || true)
    if [ -z "$found" ]; then
        pass "helper skills (setup-wizard/update-wizard/feedback) free of stale '$stale' reference"
    else
        fail "helper skills still contain '$stale': $found"
    fi
done

# AGENTS.md is the primary instruction file for OpenCode
if [ -f "$REPO_ROOT/AGENTS.md" ]; then
    pass "AGENTS.md exists at repo root"
else
    fail "AGENTS.md missing at repo root"
fi

# AGENTS.md must mention SDLC BASELINE (the per-prompt content moved here per OpenCode adaptation)
if grep -q "SDLC Baseline" "$REPO_ROOT/AGENTS.md"; then
    pass "AGENTS.md contains SDLC Baseline section"
else
    fail "AGENTS.md missing SDLC Baseline section (the per-prompt-hook replacement)"
fi

# AGENTS.md must list the 4 skills
for sk in sdlc setup update feedback; do
    if grep -qE "\b$sk\b" "$REPO_ROOT/AGENTS.md"; then
        pass "AGENTS.md mentions $sk skill"
    else
        fail "AGENTS.md missing $sk skill reference"
    fi
done

# install.sh present + executable
if [ -x "$REPO_ROOT/install.sh" ]; then
    pass "install.sh present and executable"
else
    fail "install.sh missing or not executable"
fi

# Backend picker + cross-model-review scripts present + executable + valid bash
for s in detect-backends.sh configure-backend.sh cross-model-review.sh; do
    if [ -x "$REPO_ROOT/scripts/$s" ]; then
        pass "scripts/$s present and executable"
    else
        fail "scripts/$s missing or not executable"
    fi
    if bash -n "$REPO_ROOT/scripts/$s" 2>/dev/null; then
        pass "scripts/$s passes bash -n syntax check"
    else
        fail "scripts/$s has bash syntax errors"
    fi
done

# install.sh references the scripts in REQUIRED_SOURCES (so they ship)
for s in detect-backends.sh configure-backend.sh cross-model-review.sh; do
    if grep -q "scripts/$s" "$REPO_ROOT/install.sh"; then
        pass "install.sh REQUIRED_SOURCES includes scripts/$s"
    else
        fail "install.sh does not list scripts/$s — bundle won't ship it"
    fi
done

# PRIVACY.md present at repo root (tier model)
if [ -f "$REPO_ROOT/PRIVACY.md" ]; then
    pass "PRIVACY.md exists at repo root"
else
    fail "PRIVACY.md missing — privacy-tier doc is part of the picker bundle"
fi
# PRIVACY.md mentions all four tier names (regression guard against tier drift)
for tier in private_local enterprise hosted_oss proprietary; do
    if grep -q "$tier" "$REPO_ROOT/PRIVACY.md"; then
        pass "PRIVACY.md documents tier '$tier'"
    else
        fail "PRIVACY.md missing tier '$tier'"
    fi
done

# Hooks are executable
for hook in $REPO_ROOT/hooks/*.sh $REPO_ROOT/.opencode/hooks/*.sh; do
    [ -x "$hook" ] && pass "$(basename "$hook") executable [$(dirname "$hook" | xargs basename)/]" || fail "$(basename "$hook") not executable [$(dirname "$hook" | xargs basename)/]"
done

# Plugin uses correct OpenCode event names (no Claude-isms leak through).
# Note: session.created is dispatched via the GENERIC `event` handler with
# event.type discriminator (per OpenCode docs), not via a direct
# "session.created" handler key. tool.execute.before and
# experimental.session.compacting use direct named-key handlers.
plugin="$REPO_ROOT/.opencode/plugins/sdlc-wizard.js"

# Generic event handler must exist for session-lifecycle dispatch
if grep -qE '^\s*event:\s*async' "$plugin"; then
    pass "plugin has generic event handler (for session.created dispatch)"
else
    fail "plugin missing generic event handler"
fi

# Generic handler must filter on session.* events. Either a strict
# `event.type === "session.created"` discriminator OR the race-resilient
# `event.type.startsWith("session.")` pattern with a dedupe flag is acceptable
# (both intercept session-lifecycle events; the latter survives OpenCode's
# session.created/plugin-init race observed live in 1.14.33).
if grep -qE 'event\.type[[:space:]]*(===|!==)[[:space:]]*"session\.created"' "$plugin" \
   || ( grep -qE 'event\.type\.startsWith\("session\."\)' "$plugin" \
        && grep -qE 'sessionStartFired' "$plugin" ); then
    pass "generic event handler intercepts session.* events (strict or race-resilient)"
else
    fail "generic event handler missing session.* discriminator (need either === \"session.created\" or .startsWith(\"session.\") + dedupe)"
fi

# Direct named-key handlers for tool.execute.before + experimental.session.compacting
for evt in "tool.execute.before" "experimental.session.compacting"; do
    if grep -qE "\"$evt\":" "$plugin"; then
        pass "plugin has named handler for $evt"
    else
        fail "plugin missing named handler for $evt"
    fi
done

# Plugin must NOT subscribe to Claude-only events (anti-leak guard)
for badevt in "UserPromptSubmit" "PreToolUse" "PreCompact" "SessionStart"; do
    # These names must only appear in comments, not as event-handler keys.
    # The handler-key form is `"<EventName>": async`. A bad leak would be that string.
    if grep -qE "\"$badevt\"[[:space:]]*:[[:space:]]*async" "$plugin"; then
        fail "plugin leaks Claude event name $badevt as handler key"
    else
        pass "plugin does not leak Claude event $badevt as handler key"
    fi
done

# Anti-regression for Codex round-1 P0 #1: `"session.created"` as a DIRECT
# handler key does not fire under OpenCode. The fix uses the generic `event`
# handler with event.type discriminator instead. Guard against the bug coming
# back via a direct handler key.
if grep -qE '"session\.created"[[:space:]]*:[[:space:]]*async' "$plugin"; then
    fail "plugin uses session.created as direct handler key (P0 — OpenCode dispatches via generic event channel)"
else
    pass "plugin does not use session.created as direct handler key (anti-regression)"
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All bundle integrity tests passed!"

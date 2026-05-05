#!/usr/bin/env bash
# Bundle drift tests — catch broken internal references at test time so
# the wizard never ships with a skill / doc that points at a script we
# removed or renamed.
#
# Triggered by v0.2.0 round-1 P1 #4 (helper skills referenced
# CLAUDE_CODE_SDLC_WIZARD.md / agentic-sdlc-wizard / .claude/settings.json
# after we'd switched to OpenCode). The Claude-specific guard already
# exists; this file extends it to OUR OWN bundle so future refactors
# don't silently break references.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "=== Bundle drift ==="

# Helper: assert every "scripts/<name>.sh" or ".opencode/scripts/<name>.sh"
# referenced in DOCS resolves to an actual file in the repo OR target
# install layout.
check_script_references() {
  local file="$1"
  local label="$2"
  # Pull script paths mentioned in the doc. Match both forms used in
  # skills + readme + install.sh: `scripts/<name>.sh` and
  # `.opencode/scripts/<name>.sh`.
  local refs
  refs=$(grep -oE "(\.opencode/)?scripts/[a-zA-Z0-9_-]+\.sh" "$file" 2>/dev/null \
           | sort -u || true)
  if [ -z "$refs" ]; then
    pass "$label: no scripts/* references (or all clean)"
    return 0
  fi
  local broken=""
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    local source_path="${ref#.opencode/}"  # strip .opencode/ prefix
    if [ ! -f "$REPO_ROOT/$source_path" ]; then
      broken="${broken:+${broken}, }$ref"
    fi
  done <<< "$refs"
  if [ -z "$broken" ]; then
    pass "$label: all scripts/* references resolve"
  else
    fail "$label: broken scripts/* references → $broken"
  fi
}

# Helper: assert every "skill/.../SKILL.md" or skill name reference
# resolves to a shipping skill in the bundle.
check_skill_references() {
  local file="$1"
  local label="$2"
  # Look for skill({ name: "<id>" }) or `skill\(<id>\)` invocations
  local refs
  refs=$( (grep -oE 'skill\(\{[^}]*name:[[:space:]]*"[a-z-]+"' "$file" 2>/dev/null || true) \
           | (grep -oE '"[a-z-]+"' || true) \
           | tr -d '"' \
           | sort -u )
  if [ -z "$refs" ]; then
    pass "$label: no skill({name}) references (or all clean)"
    return 0
  fi
  local broken=""
  while IFS= read -r skill_name; do
    [ -z "$skill_name" ] && continue
    if [ ! -f "$REPO_ROOT/skills/$skill_name/SKILL.md" ]; then
      broken="${broken:+${broken}, }$skill_name"
    fi
  done <<< "$refs"
  if [ -z "$broken" ]; then
    pass "$label: all skill({name}) references resolve"
  else
    fail "$label: broken skill name references → $broken"
  fi
}

# T1-T2: every shipping skill's references resolve
for sk in sdlc setup-wizard update-wizard feedback cross-model-review; do
  if [ -f "$REPO_ROOT/skills/$sk/SKILL.md" ]; then
    check_script_references "$REPO_ROOT/skills/$sk/SKILL.md" "skills/$sk/SKILL.md"
    check_skill_references "$REPO_ROOT/skills/$sk/SKILL.md" "skills/$sk/SKILL.md"
  fi
done

# T3: AGENTS.md script + skill references resolve
check_script_references "$REPO_ROOT/AGENTS.md" "AGENTS.md"
check_skill_references "$REPO_ROOT/AGENTS.md" "AGENTS.md"

# T4: README script references resolve
check_script_references "$REPO_ROOT/README.md" "README.md"

# T5: PRIVACY.md script references resolve
check_script_references "$REPO_ROOT/PRIVACY.md" "PRIVACY.md"

# T6: install.sh REQUIRED_SOURCES + declare_target stay in sync.
# Every source listed in REQUIRED_SOURCES must have a matching
# declare_target case (otherwise it falls through to *) which silently
# installs at the source path).
# Extract REQUIRED_SOURCES entries (only the array lines, not the
# .opencode/hooks/* wildcard which is handled by a glob case).
required_in_install="$(awk '/REQUIRED_SOURCES=\(/,/^\)/' "$REPO_ROOT/install.sh" \
                          | grep -oE '"[^"]+"' \
                          | tr -d '"' \
                          | grep -v '^\.opencode/hooks/' \
                          | sort -u || true)"
# Extract declare_target case keys (left-hand side of the case patterns)
declare_targets="$(awk '/declare_target\(\)/,/^\}/' "$REPO_ROOT/install.sh" \
                      | grep -oE '"[^"]+"\)' \
                      | grep -oE '"[^"]+"' \
                      | tr -d '"' \
                      | sort -u || true)"

missing_targets=""
while IFS= read -r src; do
  [ -z "$src" ] && continue
  if ! echo "$declare_targets" | grep -qx "$src"; then
    missing_targets="${missing_targets:+${missing_targets}, }$src"
  fi
done <<< "$required_in_install"
if [ -z "$missing_targets" ]; then
  pass "install.sh: REQUIRED_SOURCES all have declare_target cases"
else
  fail "install.sh REQUIRED_SOURCES without declare_target case → $missing_targets"
fi

# T7: every script in scripts/ that's still in the source tree must be
# listed in install.sh (or it ships in the tarball but never reaches
# the target's .opencode/scripts/)
for s in "$REPO_ROOT"/scripts/*.sh; do
  [ -f "$s" ] || continue
  base="$(basename "$s")"
  if grep -qE "scripts/$base" "$REPO_ROOT/install.sh"; then
    pass "scripts/$base is shipped by install.sh"
  else
    fail "scripts/$base exists but install.sh never installs it"
  fi
done

# T8: every skill dir in skills/ must be listed in install.sh
for d in "$REPO_ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  if grep -qE "skills/$base/SKILL\.md" "$REPO_ROOT/install.sh"; then
    pass "skills/$base/ is shipped by install.sh"
  else
    fail "skills/$base/ exists but install.sh never installs it"
  fi
done

# T9: hooks must not reference parent-wizard npm packages (caught a
# real bug in v0.4.1 — `npm view agentic-sdlc-wizard version` was
# pointing the version-staleness nudge at the wrong wizard, so users
# of opencode-sdlc-wizard would see wrong-package upgrade prompts).
# Comments referencing the parent are OK (informational), so we limit
# this check to lines that look like an EXECUTABLE reference: an
# npm/git/curl/install command line.
for hook in "$REPO_ROOT"/.opencode/hooks/*.sh "$REPO_ROOT"/hooks/*.sh; do
  [ -f "$hook" ] || continue
  base="$(basename "$hook")"
  parent_dir="$(dirname "$hook" | xargs basename)/"
  # Lines that EXECUTE something against the parent's package or repo
  bad=$(grep -E "^[[:space:]]*[^#].*((npm[[:space:]]+(view|install)[[:space:]]+(agentic|claude)-sdlc-wizard)|(BaseInfinity/(claude|agentic)-sdlc-wizard)|(claude-sdlc-wizard\.git))" "$hook" 2>/dev/null || true)
  if [ -z "$bad" ]; then
    pass "${parent_dir}${base}: no executable refs to parent wizard packages"
  else
    fail "${parent_dir}${base}: executable parent-wizard ref → $(echo "$bad" | head -1)"
  fi
done

# T10: hooks dual-location no-drift — every .opencode/hooks/<f> must
# byte-match hooks/<f>. Already covered by test-bundle-integrity but
# included here as defense-in-depth since drift between mirrors is a
# subtle silent failure.
for h in _find-sdlc-root.sh sdlc-prompt-check.sh tdd-pretool-check.sh \
         instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh; do
  if cmp -s "$REPO_ROOT/.opencode/hooks/$h" "$REPO_ROOT/hooks/$h" 2>/dev/null; then
    pass "drift-guard: hooks/$h == .opencode/hooks/$h"
  else
    fail "drift-guard: hooks/$h differs from .opencode/hooks/$h (mirror drift)"
  fi
done

# T11: skill dir name == frontmatter name (already covered by
# bundle-integrity, here as redundant guard since this is a drift class)
for d in "$REPO_ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  fm_name="$(awk '/^name:/ {print $2; exit}' "$d/SKILL.md" 2>/dev/null)"
  if [ "$fm_name" = "$base" ]; then
    pass "drift-guard: skills/$base SKILL.md frontmatter name matches dir"
  else
    fail "drift-guard: skills/$base/SKILL.md frontmatter name='$fm_name' but dir='$base'"
  fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All bundle-drift tests passed!"

#!/usr/bin/env bash
# OpenCode SDLC Wizard installer.
#
# Non-destructive merge of the wizard into a target repo's .opencode/ dir.
# Pattern mirrors codex-sdlc-wizard's install.sh (battle-tested across
# 6 config-merge cases). Differences here: no TOML config (OpenCode uses
# opencode.json), plus a JS plugin shim instead of a hooks.json registration.
#
# Usage:
#   bash install.sh [--target-dir PATH] [--force]
#
# Default --target-dir is the current working directory.
#
# Idempotent: re-running on an already-installed repo is safe — files are only
# overwritten with --force; otherwise existing customizations are preserved
# and a per-file MATCH/CUSTOMIZED/MISSING report is printed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target-dir)
      shift
      [ $# -eq 0 ] && { echo "Missing value for --target-dir" >&2; exit 1; }
      TARGET_DIR="$1"
      ;;
    --target-dir=*) TARGET_DIR="${1#*=}" ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ ! -d "$TARGET_DIR" ]; then
  echo "Target dir does not exist: $TARGET_DIR" >&2
  exit 1
fi

WIZARD_VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCRIPT_DIR/package.json" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
[ -z "$WIZARD_VERSION" ] && WIZARD_VERSION="unknown"

echo "OpenCode SDLC Wizard v$WIZARD_VERSION"
echo "Target: $TARGET_DIR"
echo ""

# Required source files in this repo (the bundle)
REQUIRED_SOURCES=(
  "AGENTS.md"
  "PRIVACY.md"
  ".opencode/plugins/sdlc-wizard.js"
  ".opencode/hooks/_find-sdlc-root.sh"
  ".opencode/hooks/sdlc-prompt-check.sh"
  ".opencode/hooks/tdd-pretool-check.sh"
  ".opencode/hooks/instructions-loaded-check.sh"
  ".opencode/hooks/model-effort-check.sh"
  ".opencode/hooks/precompact-seam-check.sh"
  "scripts/detect-backends.sh"
  "scripts/configure-backend.sh"
  "scripts/cross-model-review.sh"
  "scripts/check-updates.sh"
  "skills/sdlc/SKILL.md"
  "skills/setup-wizard/SKILL.md"
  "skills/update-wizard/SKILL.md"
  "skills/feedback/SKILL.md"
  "skills/cross-model-review/SKILL.md"
  "templates/testing/firmware.md"
  "templates/testing/data-science.md"
  "templates/testing/cli.md"
  "templates/testing/web.md"
  "templates/sdlc.md"
  "templates/architecture.md"
)

for f in "${REQUIRED_SOURCES[@]}"; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo "Bundle is missing: $f" >&2
    echo "Re-install the wizard or report a bug." >&2
    exit 1
  fi
done

# Map source path → target path (target uses .opencode/ for everything plugin-side,
# .opencode/skills/ for skills so OpenCode discovers them natively)
declare_target() {
  case "$1" in
    "AGENTS.md") echo "AGENTS.md" ;;
    "PRIVACY.md") echo "PRIVACY.md" ;;
    ".opencode/plugins/sdlc-wizard.js") echo ".opencode/plugins/sdlc-wizard.js" ;;
    ".opencode/hooks/"*) echo "$1" ;;
    "scripts/detect-backends.sh") echo ".opencode/scripts/detect-backends.sh" ;;
    "scripts/configure-backend.sh") echo ".opencode/scripts/configure-backend.sh" ;;
    "scripts/cross-model-review.sh") echo ".opencode/scripts/cross-model-review.sh" ;;
    "scripts/check-updates.sh") echo ".opencode/scripts/check-updates.sh" ;;
    "skills/sdlc/SKILL.md") echo ".opencode/skills/sdlc/SKILL.md" ;;
    "skills/setup-wizard/SKILL.md") echo ".opencode/skills/setup-wizard/SKILL.md" ;;
    "skills/update-wizard/SKILL.md") echo ".opencode/skills/update-wizard/SKILL.md" ;;
    "skills/feedback/SKILL.md") echo ".opencode/skills/feedback/SKILL.md" ;;
    "skills/cross-model-review/SKILL.md") echo ".opencode/skills/cross-model-review/SKILL.md" ;;
    "templates/testing/firmware.md") echo ".opencode/templates/testing/firmware.md" ;;
    "templates/testing/data-science.md") echo ".opencode/templates/testing/data-science.md" ;;
    "templates/testing/cli.md") echo ".opencode/templates/testing/cli.md" ;;
    "templates/testing/web.md") echo ".opencode/templates/testing/web.md" ;;
    "templates/sdlc.md") echo ".opencode/templates/sdlc.md" ;;
    "templates/architecture.md") echo ".opencode/templates/architecture.md" ;;
    *) echo "$1" ;;
  esac
}

# File classification: MATCH / CUSTOMIZED / MISSING
classify() {
  local src_abs="$1"
  local dst_abs="$2"
  if [ ! -f "$dst_abs" ]; then
    echo "MISSING"
    return
  fi
  if cmp -s "$src_abs" "$dst_abs"; then
    echo "MATCH"
  else
    echo "CUSTOMIZED"
  fi
}

INSTALLED=0
SKIPPED=0
UPDATED=0

for src_rel in "${REQUIRED_SOURCES[@]}"; do
  dst_rel="$(declare_target "$src_rel")"
  src_abs="$SCRIPT_DIR/$src_rel"
  dst_abs="$TARGET_DIR/$dst_rel"
  status="$(classify "$src_abs" "$dst_abs")"

  case "$status" in
    MATCH)
      printf "  MATCH       %s\n" "$dst_rel"
      ;;
    MISSING)
      mkdir -p "$(dirname "$dst_abs")"
      cp "$src_abs" "$dst_abs"
      printf "  INSTALLED   %s\n" "$dst_rel"
      INSTALLED=$((INSTALLED + 1))
      ;;
    CUSTOMIZED)
      if [ "$FORCE" -eq 1 ]; then
        cp "$src_abs" "$dst_abs"
        printf "  OVERWROTE   %s (--force)\n" "$dst_rel"
        UPDATED=$((UPDATED + 1))
      else
        printf "  CUSTOMIZED  %s (kept; rerun with --force to overwrite)\n" "$dst_rel"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
  esac
done

# Make hook + script files executable
for d in "$TARGET_DIR/.opencode/hooks" "$TARGET_DIR/.opencode/scripts"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.sh; do
    [ -f "$f" ] && chmod +x "$f"
  done
done

# Drop a metadata stamp so update/check can detect drift later. Only
# (re)write the stamp when something actually changed — preserves the
# original installed_at on no-op re-runs (idempotency).
META_DIR="$TARGET_DIR/.opencode"
mkdir -p "$META_DIR"
STAMP_FILE="$META_DIR/.wizard-stamp"
if [ ! -f "$STAMP_FILE" ] || [ "$INSTALLED" -gt 0 ] || [ "$UPDATED" -gt 0 ]; then
  {
    echo "# Managed by opencode-sdlc-wizard. Do not edit by hand."
    echo "wizard_version=$WIZARD_VERSION"
    echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STAMP_FILE"
fi

echo ""
echo "Summary: $INSTALLED installed, $UPDATED overwrote, $SKIPPED kept-customized."
echo ""

if [ "$INSTALLED" -gt 0 ] || [ "$UPDATED" -gt 0 ]; then
  cat <<EOF
Next steps:
  1. Open OpenCode in this directory. AGENTS.md will be auto-loaded.
  2. The plugin (.opencode/plugins/sdlc-wizard.js) auto-loads at session start
     and shells out to .opencode/hooks/ for SDLC enforcement.
  3. (Optional) Pick a backend — privacy-first picker:
       bash .opencode/scripts/detect-backends.sh         # see what's available
       bash .opencode/scripts/configure-backend.sh \\
            --tier private_local --provider ollama \\
            --model qwen2.5-coder:32b
     Tiers: private_local (Ollama / LM Studio / llama.cpp / vLLM),
            enterprise (Azure / Bedrock), hosted_oss (Together / Groq /
            OpenRouter), proprietary (Anthropic / OpenAI). See PRIVACY.md.
  4. Run skill({ name: "sdlc" }) inside OpenCode to invoke the SDLC workflow.

The installer does not write opencode.json on its own — backend selection is
opt-in via the configure-backend.sh script (or the setup-wizard skill).

EOF
fi

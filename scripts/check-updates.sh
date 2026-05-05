#!/usr/bin/env bash
# Check whether the installed opencode-sdlc-wizard is behind the latest
# published version.
#
# Reads .opencode/.wizard-stamp (written by install.sh) for the
# installed version, fetches the latest via `npm view`, compares semver.
#
# Exit codes:
#   0 — installed >= latest (current)
#   1 — installed <  latest (behind)
#   2 — no stamp (not installed) or other diagnostic exit
#
# Modes:
#   default        Human-readable line on stdout
#   --json         Machine-readable {"installed","latest","status"} JSON
#   --help         Usage
#
# Env override (used by tests):
#   CHECK_UPDATES_LATEST_OVERRIDE   Forces "latest" instead of npm fetch.

set -uo pipefail

JSON=0
TARGET_DIR="$(pwd)"

usage() {
  cat <<'EOF'
check-updates.sh — opencode-sdlc-wizard staleness check

Usage:
  check-updates.sh [--target-dir PATH] [--json]
  check-updates.sh --help

Reads .opencode/.wizard-stamp for the installed version, fetches the
latest published opencode-sdlc-wizard via npm, compares via semver.

Exit codes:
  0 — installed >= latest (current)
  1 — installed <  latest (behind)
  2 — no stamp (not installed) or fetch failed

Modes:
  default      Human-readable line on stdout
  --json       Machine-readable {"installed","latest","status","target_dir"}
  --help       This message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --target-dir) shift; TARGET_DIR="${1:-}" ;;
    --target-dir=*) TARGET_DIR="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

emit_human() {
  # $1 = installed, $2 = latest, $3 = status (current|behind|missing)
  case "$3" in
    current) echo "opencode-sdlc-wizard is up-to-date ($1 == $2)" ;;
    behind)  echo "opencode-sdlc-wizard is BEHIND: installed=$1, latest=$2 (run 'npx opencode-sdlc-wizard init --force' to update, or invoke skill({ name: \"update-wizard\" }) for a smart update)" ;;
    missing) echo "No .opencode/.wizard-stamp found at $TARGET_DIR — wizard is not installed in this directory." ;;
  esac
}

emit_json() {
  printf '{"installed":"%s","latest":"%s","status":"%s","target_dir":"%s"}\n' \
    "${1:-}" "${2:-}" "${3:-}" "$TARGET_DIR"
}

# 1) Find the stamp
STAMP_FILE="$TARGET_DIR/.opencode/.wizard-stamp"
if [ ! -f "$STAMP_FILE" ]; then
  if [ "$JSON" = "1" ]; then emit_json "" "" "missing"; else emit_human "" "" "missing"; fi
  exit 2
fi

INSTALLED="$(grep -E '^wizard_version=' "$STAMP_FILE" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
if [ -z "$INSTALLED" ]; then
  if [ "$JSON" = "1" ]; then emit_json "" "" "missing"; else emit_human "" "" "missing"; fi
  exit 2
fi

# 2) Discover latest
if [ -n "${CHECK_UPDATES_LATEST_OVERRIDE:-}" ]; then
  LATEST="$CHECK_UPDATES_LATEST_OVERRIDE"
elif command -v npm >/dev/null 2>&1; then
  LATEST="$(npm view opencode-sdlc-wizard version 2>/dev/null || true)"
else
  LATEST=""
fi

if [ -z "$LATEST" ]; then
  echo "Could not determine latest version (no npm or fetch failed)." >&2
  if [ "$JSON" = "1" ]; then emit_json "$INSTALLED" "" "unknown"; fi
  exit 2
fi

# 3) Compare semver. Pure-bash compare on dotted x.y.z; tolerates extra
# label suffixes by stripping them (e.g., "0.5.0-rc1" → "0.5.0").
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+'
ICORE="$(echo "$INSTALLED" | grep -oE "$SEMVER_RE" | head -1)"
LCORE="$(echo "$LATEST"    | grep -oE "$SEMVER_RE" | head -1)"
ICORE="${ICORE:-0.0.0}"
LCORE="${LCORE:-0.0.0}"

# Compare component-by-component
IFS=. read -r I_MAJOR I_MINOR I_PATCH <<< "$ICORE"
IFS=. read -r L_MAJOR L_MINOR L_PATCH <<< "$LCORE"

status="current"
for pair in "$I_MAJOR $L_MAJOR" "$I_MINOR $L_MINOR" "$I_PATCH $L_PATCH"; do
  set -- $pair
  if [ "$1" -lt "$2" ]; then status="behind"; break; fi
  if [ "$1" -gt "$2" ]; then status="current"; break; fi
done

if [ "$JSON" = "1" ]; then
  emit_json "$INSTALLED" "$LATEST" "$status"
else
  emit_human "$INSTALLED" "$LATEST" "$status"
fi

case "$status" in
  current) exit 0 ;;
  behind)  exit 1 ;;
  *)       exit 2 ;;
esac

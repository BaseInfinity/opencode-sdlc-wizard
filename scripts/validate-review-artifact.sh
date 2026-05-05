#!/usr/bin/env bash
# validate-review-artifact.sh — wraps validate-review-artifact.js for CLI use.
#
# Usage:
#   validate-review-artifact.sh <artifact.json> <schema.json>
#   validate-review-artifact.sh --help
#
# Exit codes are passed through from the underlying node validator:
#   0 — artifact validates
#   1 — artifact fails validation (errors on stderr)
#   2 — usage / missing-file / unparseable JSON

set -uo pipefail

usage() {
  cat <<'EOF'
validate-review-artifact.sh — JSON Schema validator for .reviews/*.json

Usage:
  validate-review-artifact.sh <artifact.json> <schema.json>
  validate-review-artifact.sh --help

Validates a review artifact (.reviews/handoff.json or .reviews/response.json)
against the matching schema shipped at .opencode/schemas/.

Exit codes:
  0 — artifact validates
  1 — artifact fails validation (errors on stderr)
  2 — usage / missing-file / unparseable JSON

Wraps the zero-dep node validator at the same path with .js extension.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ $# -ne 2 ]; then
  usage >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "validate-review-artifact: node is required but not found on PATH" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JS="${SCRIPT_DIR}/validate-review-artifact.js"
if [ ! -f "$JS" ]; then
  echo "validate-review-artifact: companion script not found: $JS" >&2
  exit 2
fi

exec node "$JS" "$@"

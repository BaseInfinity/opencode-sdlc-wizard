#!/usr/bin/env bash
# Tests for v0.7.0 — JSON schemas for .reviews/{handoff,response}.json
# plus the zero-dep validator at scripts/validate-review-artifact.{sh,js}.
#
# Schemas codify the structures we've been hand-writing across review
# rounds so ditto v0.1.0 + the cross-model-review skill can consume them
# safely. This suite asserts:
#   - schemas exist + parse + declare draft-07
#   - the live .reviews/* artifacts validate against the schemas
#   - negative cases (missing required, wrong type, bad enum, conditional
#     branches for FIXED + REJECTED findings) fail with the right error
#   - the validator script handles missing-file + bad-JSON gracefully

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANDOFF_SCHEMA="$REPO_ROOT/templates/schemas/handoff.schema.json"
RESPONSE_SCHEMA="$REPO_ROOT/templates/schemas/response.schema.json"
VALIDATOR="$REPO_ROOT/scripts/validate-review-artifact.sh"
LIVE_HANDOFF="$REPO_ROOT/.reviews/handoff.json"
LIVE_RESPONSE="$REPO_ROOT/.reviews/response.json"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/schema-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== Review-artifact schemas + validator ==="

# T1-T2: schemas exist
for s in "$HANDOFF_SCHEMA" "$RESPONSE_SCHEMA"; do
  if [ -f "$s" ]; then
    pass "schema exists: ${s#$REPO_ROOT/}"
  else
    fail "schema missing: ${s#$REPO_ROOT/}"
  fi
done

# T3-T4: schemas parse as JSON
for s in "$HANDOFF_SCHEMA" "$RESPONSE_SCHEMA"; do
  if node -e "JSON.parse(require('fs').readFileSync('$s','utf8'))" 2>/dev/null; then
    pass "schema parses: ${s#$REPO_ROOT/}"
  else
    fail "schema does not parse: ${s#$REPO_ROOT/}"
  fi
done

# T5-T6: schemas declare draft-07
for s in "$HANDOFF_SCHEMA" "$RESPONSE_SCHEMA"; do
  if grep -q 'draft-07/schema' "$s"; then
    pass "schema declares draft-07: ${s#$REPO_ROOT/}"
  else
    fail "schema does not declare draft-07: ${s#$REPO_ROOT/}"
  fi
done

# T7: validator script exists + executable
if [ -x "$VALIDATOR" ]; then
  pass "validate-review-artifact.sh is executable"
else
  fail "validate-review-artifact.sh missing or not executable"
fi

# T8: --help works
if "$VALIDATOR" --help 2>&1 | grep -qi 'usage:'; then
  pass "validator --help prints usage"
else
  fail "validator --help missing 'Usage:'"
fi

# T9: no-arg usage exits 2 (usage error)
set +e
"$VALIDATOR" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "validator with no args exits 2"
else
  fail "validator with no args returned rc=$rc, expected 2"
fi

# T10: missing artifact exits 2
set +e
"$VALIDATOR" "$TMP_ROOT/does-not-exist.json" "$HANDOFF_SCHEMA" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "validator on missing artifact exits 2"
else
  fail "validator on missing artifact returned rc=$rc, expected 2"
fi

# T11: missing schema exits 2
echo '{"review_id":"x"}' > "$TMP_ROOT/probe.json"
set +e
"$VALIDATOR" "$TMP_ROOT/probe.json" "$TMP_ROOT/no-schema.json" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "validator on missing schema exits 2"
else
  fail "validator on missing schema returned rc=$rc, expected 2"
fi

# T12: unparseable artifact exits 2
echo 'not json' > "$TMP_ROOT/garbage.json"
set +e
"$VALIDATOR" "$TMP_ROOT/garbage.json" "$HANDOFF_SCHEMA" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "validator on unparseable JSON exits 2"
else
  fail "validator on unparseable JSON returned rc=$rc, expected 2"
fi

# T13: live handoff.json validates (when present)
# Validate-if-present semantics: absence is not a failure mode. A clean
# checkout (CI runner, fresh clone) won't have an in-flight handoff. Local
# dev sessions in the middle of a review WILL have one and we want to
# catch schema regressions then. `.reviews/handoff.json` is currently
# tracked but the same file may also be gitignored on consumer installs.
if [ -f "$LIVE_HANDOFF" ]; then
  set +e
  out="$("$VALIDATOR" "$LIVE_HANDOFF" "$HANDOFF_SCHEMA" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^OK '; then
    pass "live .reviews/handoff.json validates against schema"
  else
    fail "live .reviews/handoff.json failed validation (rc=$rc): $out"
  fi
else
  pass "live .reviews/handoff.json absent — skipped (validate-if-present)"
fi

# T14: live response.json validates (when present)
# Per .gitignore, `.reviews/response.json` is per-cycle scratch and not
# tracked. Absence is the default in CI; only enforce schema validation
# when a maintainer is mid-review locally.
if [ -f "$LIVE_RESPONSE" ]; then
  set +e
  out="$("$VALIDATOR" "$LIVE_RESPONSE" "$RESPONSE_SCHEMA" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^OK '; then
    pass "live .reviews/response.json validates against schema"
  else
    fail "live .reviews/response.json failed validation (rc=$rc): $out"
  fi
else
  pass "live .reviews/response.json absent — skipped (validate-if-present)"
fi

# Negative-case fixtures
HANDOFF_BAD_MISSING="$TMP_ROOT/handoff-missing-required.json"
cat > "$HANDOFF_BAD_MISSING" <<'JSON'
{
  "review_id": "test-001",
  "status": "PENDING_REVIEW",
  "round": 1
}
JSON

HANDOFF_BAD_ENUM="$TMP_ROOT/handoff-bad-enum.json"
cat > "$HANDOFF_BAD_ENUM" <<'JSON'
{
  "review_id": "test-002",
  "status": "BOGUS",
  "round": 1,
  "mission": "x",
  "success": "y",
  "failure": "z",
  "review_instructions": "w"
}
JSON

HANDOFF_BAD_TYPE="$TMP_ROOT/handoff-bad-type.json"
cat > "$HANDOFF_BAD_TYPE" <<'JSON'
{
  "review_id": "test-003",
  "status": "PENDING_REVIEW",
  "round": "one",
  "mission": "x",
  "success": "y",
  "failure": "z",
  "review_instructions": "w"
}
JSON

# T15: missing required fields fails with rc=1 + reports each missing field
set +e
out="$("$VALIDATOR" "$HANDOFF_BAD_MISSING" "$HANDOFF_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'mission.*required field missing' \
   && echo "$out" | grep -q 'success.*required field missing' \
   && echo "$out" | grep -q 'failure.*required field missing' \
   && echo "$out" | grep -q 'review_instructions.*required field missing'; then
  pass "missing required fields → rc=1 + each reported"
else
  fail "missing required fields not reported correctly (rc=$rc): $out"
fi

# T16: bad enum fails with rc=1 + enum violation
set +e
out="$("$VALIDATOR" "$HANDOFF_BAD_ENUM" "$HANDOFF_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'status.*enum violation'; then
  pass "bad status enum → rc=1 + enum violation"
else
  fail "bad enum not reported correctly (rc=$rc): $out"
fi

# T17: wrong type fails with rc=1 + type mismatch
set +e
out="$("$VALIDATOR" "$HANDOFF_BAD_TYPE" "$HANDOFF_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'round.*type mismatch'; then
  pass "wrong type → rc=1 + type mismatch"
else
  fail "wrong type not reported correctly (rc=$rc): $out"
fi

# T18: response.json — FIXED status without fix_summary/fix_locations fails
RESP_FIXED_BARE="$TMP_ROOT/response-fixed-bare.json"
cat > "$RESP_FIXED_BARE" <<'JSON'
{
  "review_id": "r-1",
  "round": 1,
  "responses": [
    { "finding_id": "F1", "severity": "P0", "title": "x", "claim": "y", "status": "FIXED" }
  ]
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_FIXED_BARE" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'fix_summary.*required field missing' \
   && echo "$out" | grep -q 'fix_locations.*required field missing'; then
  pass "FIXED status without fix_summary/fix_locations → rc=1"
else
  fail "FIXED conditional not enforced (rc=$rc): $out"
fi

# T19: response.json — REJECTED status without rejection_reason fails
RESP_REJECTED_BARE="$TMP_ROOT/response-rejected-bare.json"
cat > "$RESP_REJECTED_BARE" <<'JSON'
{
  "review_id": "r-2",
  "round": 1,
  "responses": [
    { "finding_id": "F1", "severity": "P1", "title": "x", "claim": "y", "status": "REJECTED" }
  ]
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_REJECTED_BARE" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'rejection_reason.*required field missing'; then
  pass "REJECTED status without rejection_reason → rc=1"
else
  fail "REJECTED conditional not enforced (rc=$rc): $out"
fi

# T20: response.json — FIXED with both fields succeeds
RESP_FIXED_OK="$TMP_ROOT/response-fixed-ok.json"
cat > "$RESP_FIXED_OK" <<'JSON'
{
  "review_id": "r-3",
  "round": 1,
  "responses": [
    {
      "finding_id": "F1",
      "severity": "P0",
      "title": "x",
      "claim": "y",
      "status": "FIXED",
      "fix_summary": "did the thing",
      "fix_locations": ["a.js:1-2"]
    }
  ]
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_FIXED_OK" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^OK '; then
  pass "FIXED status with fix_summary + fix_locations → rc=0"
else
  fail "FIXED status with fields should succeed (rc=$rc): $out"
fi

# T21: response.json — bad severity pattern (P3) fails
RESP_BAD_SEV="$TMP_ROOT/response-bad-severity.json"
cat > "$RESP_BAD_SEV" <<'JSON'
{
  "review_id": "r-4",
  "round": 1,
  "responses": [
    {
      "finding_id": "F1",
      "severity": "P3",
      "title": "x",
      "claim": "y",
      "status": "OPEN"
    }
  ]
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_BAD_SEV" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'severity.*pattern violation'; then
  pass "P3 severity → pattern violation"
else
  fail "P3 severity not caught (rc=$rc): $out"
fi

# T22: response.json — parenthetical severity allowed
RESP_PAREN_SEV="$TMP_ROOT/response-paren-severity.json"
cat > "$RESP_PAREN_SEV" <<'JSON'
{
  "review_id": "r-5",
  "round": 1,
  "responses": [
    {
      "finding_id": "E2E-RACE",
      "severity": "P0 (caught by live E2E, NOT in round-2)",
      "title": "x",
      "claim": "y",
      "status": "FIXED",
      "fix_summary": "f",
      "fix_locations": ["x:1"]
    }
  ]
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_PAREN_SEV" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "P0 with parenthetical context → accepted"
else
  fail "parenthetical severity context rejected (rc=$rc): $out"
fi

# T23: response.json — recheck_instructions_for_round_N pattern key matched
RESP_RECHECK="$TMP_ROOT/response-recheck.json"
cat > "$RESP_RECHECK" <<'JSON'
{
  "review_id": "r-6",
  "round": 2,
  "responses": [],
  "recheck_instructions_for_round_3": "verify F1-F6 fixes",
  "recheck_instructions_for_round_99": "future-proof key"
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_RECHECK" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "recheck_instructions_for_round_N pattern keys accepted"
else
  fail "pattern key rejected (rc=$rc): $out"
fi

# T24: bundle test — schemas reachable from .opencode/schemas/ after install
INSTALL_TEST="$TMP_ROOT/install-target"
mkdir -p "$INSTALL_TEST"
bash "$REPO_ROOT/install.sh" --target-dir "$INSTALL_TEST" >/dev/null 2>&1
if [ -f "$INSTALL_TEST/.opencode/schemas/handoff.schema.json" ] \
   && [ -f "$INSTALL_TEST/.opencode/schemas/response.schema.json" ]; then
  pass "install lands schemas at .opencode/schemas/"
else
  fail "install did not land schemas"
fi

# T25: validator installed at .opencode/scripts/
if [ -x "$INSTALL_TEST/.opencode/scripts/validate-review-artifact.sh" ] \
   && [ -f "$INSTALL_TEST/.opencode/scripts/validate-review-artifact.js" ]; then
  pass "install lands validator (sh+js) at .opencode/scripts/"
else
  fail "install did not land validator"
fi

# T26: installed validator + schemas validate the live artifacts together
set +e
out="$("$INSTALL_TEST/.opencode/scripts/validate-review-artifact.sh" \
       "$LIVE_HANDOFF" \
       "$INSTALL_TEST/.opencode/schemas/handoff.schema.json" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^OK '; then
  pass "installed validator + installed schema together validate live handoff"
else
  fail "installed pair failed live handoff validation (rc=$rc): $out"
fi

# T27: validator JS file is also picked up by package.json files[]
# (covered by install — if scripts/ is in files[], the .js ships too)
if grep -q '"scripts/"' "$REPO_ROOT/package.json"; then
  pass "package.json files[] includes scripts/ (validator.js will publish)"
else
  fail "package.json files[] missing scripts/"
fi

# T28: package.json files[] includes templates/ (schemas dir lives under it)
if grep -q '"templates/"' "$REPO_ROOT/package.json"; then
  pass "package.json files[] includes templates/ (schemas/ dir will publish)"
else
  fail "package.json files[] missing templates/"
fi

# T29: codex round-1 F5 regression — schema-valued additionalProperties
# Schemas use additionalProperties: { type: integer, minimum: 0 } for
# verification_state.test_counts. Non-integer or negative values must fail.
RESP_BAD_TC="$TMP_ROOT/response-bad-test-counts.json"
cat > "$RESP_BAD_TC" <<'JSON'
{
  "review_id": "r-bad-tc",
  "round": 1,
  "responses": [],
  "verification_state": {
    "tests_green": true,
    "test_counts": {"total": 100, "bad": "not-int", "negative": -1}
  }
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_BAD_TC" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'test_counts/bad.*type mismatch' \
   && echo "$out" | grep -q 'test_counts/negative.*minimum violation'; then
  pass "schema-valued additionalProperties enforced on test_counts (F5 fix)"
else
  fail "F5 regression — schema-valued addProps not enforced (rc=$rc): $out"
fi

# T30: schema-valued additionalProperties — valid integers still pass
RESP_GOOD_TC="$TMP_ROOT/response-good-test-counts.json"
cat > "$RESP_GOOD_TC" <<'JSON'
{
  "review_id": "r-good-tc",
  "round": 1,
  "responses": [],
  "verification_state": {
    "tests_green": true,
    "test_counts": {"total": 285, "suite_a": 73, "suite_b": 11}
  }
}
JSON
set +e
out="$("$VALIDATOR" "$RESP_GOOD_TC" "$RESPONSE_SCHEMA" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^OK '; then
  pass "schema-valued additionalProperties — valid integer test_counts pass"
else
  fail "valid test_counts should pass (rc=$rc): $out"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

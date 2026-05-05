# Releasing opencode-sdlc-wizard

Repeatable release flow. Each version takes ~2 minutes once you've done it once.

## Cutting a new version

From a clean `main` with all v0.X.Y work merged + green tests:

```bash
# 1. Bump version (npm rewrites package.json + creates a vX.Y.Z tag)
npm version <patch|minor|major>

# 2. Push commit + tag together
AFTERHOURS_SKIP=1 git push origin main --follow-tags
```

The push triggers `.github/workflows/release.yml`, which:

1. Verifies tag is on `main` and matches `package.json` version
2. Runs `npm test` (113/113 must pass)
3. Calls `npm publish --provenance --access public` using the
   `NPM_TOKEN` repo secret
4. Creates a GitHub release with auto-generated notes

If the workflow lights green: done. v`X.Y.Z` is on npm + a release exists.

## When the workflow fails the npm publish step

This happens when your npm account has **2FA on writes** (the strictest
mode), even with an automation token. Symptom: the workflow logs show
`npm error code E404 - PUT /<package>` after the provenance attestation
is signed.

Two ways to resolve:

### Option A — manual OTP publish (one extra step per release)

```bash
# After the workflow fails at npm publish:
npm publish --access public --otp=<6-digit-code>

# Then create the GitHub release manually:
gh release create vX.Y.Z --generate-notes -R BaseInfinity/opencode-sdlc-wizard
```

### Option B — switch npm 2FA mode to "auth-only" (forever zero-touch)

Visit https://www.npmjs.com/settings/baseinfinity/profile → 2FA section
→ change from "Auth and writes" to "Auth only". Automation tokens then
bypass 2FA on publish; the workflow becomes hands-off for every future
release. (You still need 2FA to log in, mint tokens, change account
settings — the change only affects publish/unpublish operations.)

**Recommended:** Option B for a wizard with frequent minor releases.
Option A if you prefer the extra friction as a brake against unintended
publishes.

## Preflight before any release

```bash
npm test                          # 113/113 must pass
npm pack --dry-run | tail -10     # tarball contents look right
git diff origin/main..HEAD        # what's actually shipping
```

## Cross-model review

Standing standard before tagging anything past v0.2.0: a Codex round-N
recheck against the last release's `.reviews/handoff.json` +
`.reviews/response.json`. Pattern documented in
`.reviews/handoff.json:review_instructions`. Skip only if the diff is
docs-only.

```bash
codex exec \
  -c 'model_reasoning_effort="xhigh"' \
  -s danger-full-access \
  -o .reviews/latest-review.md \
  "ROUND-N RECHECK ..." </dev/null
```

The `</dev/null` is required — codex hangs on stdin without it (verified
v0.128.0).

## After the release lands

- Mirror issues in the three sibling repos so their READMEs add OpenCode
  to the ecosystem table:
  ```bash
  for REPO in claude-sdlc-wizard codex-sdlc-wizard claude-gdlc-wizard; do
    gh issue create -R "BaseInfinity/$REPO" \
      --title "Add opencode-sdlc-wizard to ecosystem table" \
      --body-file MIRROR_ISSUE_BODY.md
  done
  ```
- Update parent `claude-sdlc-wizard`'s ROADMAP #9 with the new tag URL.
- Bump the npm package readme + GitHub topic tags if positioning changes.

## Capability floor (Phase B reminder)

A failed install or run on a model below the 30B+ code-tuned class
(Qwen2.5-Coder, DeepSeek-Coder, Sonnet, Opus, GPT-5.x) is a capability
result, not a release bug. Don't gate releases on small-local-model
performance.

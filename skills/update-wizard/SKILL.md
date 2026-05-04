---
name: update-wizard
description: Smart update for the OpenCode SDLC wizard — shows what changed, classifies drift per file (MATCH/CUSTOMIZED/MISSING), lets the user selectively adopt while preserving customizations.
---

# Update Wizard

## Purpose

Reconcile drift between the user's installed `.opencode/` artifacts and
the latest upstream `opencode-sdlc-wizard` release. The wizard's
philosophy is the same as the parent: never silently overwrite,
always preserve user customizations unless the user explicitly says
otherwise.

## Reasoning policy

`xhigh` for update flows. Drift detection is a careful, branching
workflow with edge cases (deleted files, renamed paths, mid-update
interrupts). Don't cut corners.

## Scope guard

Update touches only:

- `.opencode/` managed files (plugins, hooks, skills)
- The wizard metadata stamp at `.opencode/.wizard-stamp`
- `AGENTS.md` (only with consent — it's user-authored content)
- `SDLC.md` metadata header (the version-tracking comment)

Update **never** touches:

- Application code
- The body of `AGENTS.md` (only the wizard-managed sections)
- `opencode.json` (user config, sacred)
- Anything outside `.opencode/`, the four wizard-managed `.md` docs,
  and `package.json`'s wizard-version field

If the user has run setup recently and there's nothing to update,
report cleanly and exit.

## Workflow

### Step 1 — Discover installed version

Read `.opencode/.wizard-stamp` and extract `wizard_version`. If absent,
treat as fresh-install (defer to `skill({ name: "setup-wizard" })`).

### Step 2 — Discover latest upstream version

Fetch the latest published `opencode-sdlc-wizard` version. Two
sources, in priority:

1. `https://registry.npmjs.org/opencode-sdlc-wizard/latest` (canonical)
2. `https://raw.githubusercontent.com/BaseInfinity/opencode-sdlc-wizard/main/package.json` (fallback)

Compare via semver. If installed >= latest, report "you're up to date"
and exit.

### Step 3 — Show CHANGELOG diff

Fetch `CHANGELOG.md` from the upstream repo and show entries between
installed and latest. The user reads what changed before deciding.

### Step 4 — Classify each managed file

For every file the wizard manages, classify against the upstream:

- **MATCH** — local file is byte-identical to upstream. No-op.
- **CUSTOMIZED** — local file diverges from upstream (user edited).
  Show diff; ask: adopt / skip / merge?
- **MISSING** — file expected by wizard doesn't exist locally. Offer
  install.
- **DRIFT** — file exists but has problems (wrong permissions, malformed
  metadata). Flag + offer fix.

### Step 5 — Apply selected updates

For each file the user opts in:

- Read upstream content from the cloned/downloaded source
- Write to local path
- Re-run `chmod +x` on hooks if applicable

### Step 6 — Bump version stamp

After all approved updates apply, bump `.opencode/.wizard-stamp`'s
`wizard_version` to the new version. If any file failed to update,
leave the stamp at the old version (so retry is idempotent).

### Step 7 — Verify

Run `bash tests/test-bundle-integrity.sh` if available in the consumer.
Report any remaining drift.

## Argument modes

- `check-only` — run Step 1-4 only; report drift, do not prompt or apply
- `force-all` — accept all upstream changes without per-file prompting
  (still shows diffs for record)
- (default, no arg) — full interactive flow

## On the AGENTS.md question

`AGENTS.md` is special. The wizard generates an initial AGENTS.md but
users typically add project-specific guidance to it. Update should:

- Diff only the **wizard-managed sections** (those between markers like
  `<!-- wizard:start -->` and `<!-- wizard:end -->`, if present)
- Leave user-authored content untouched
- If no markers exist (older installs), surface the full diff and let
  the user choose

This is a manual reconciliation surface; don't automate it past the
"show me the diff" step.

---
name: feedback
description: Privacy-first feedback loop for OpenCode SDLC wizard usage — capture bugs, feature requests, patterns, and improvements without scanning the repo unless the user explicitly allows it.
---

# Feedback

## Purpose

Help the user contribute back to the OpenCode SDLC wizard:

- bug reports
- feature requests
- working patterns
- process improvements

Privacy first. Never scan the repo without explicit permission.

## Mandatory permission rule

Before scanning anything beyond obvious SDLC file names, ask first.

Use this exact shape when asking:

> "I can scan your SDLC setup to identify what you've customized versus
> wizard defaults. This helps me create a more specific report. May I
> scan? Only SDLC file names and config are read — no source code,
> secrets, or business logic."

Only scan:

- repo-local SDLC docs (`AGENTS.md`, `SDLC.md`, `TESTING.md`,
  `ARCHITECTURE.md`)
- hook file names and which hooks are active (`.opencode/hooks/`)
- skill directory names (`.opencode/skills/`)
- `.opencode/.wizard-stamp` (wizard version + install date)

**Never read** application code, `opencode.json`'s provider keys,
`.env` files, secrets, git history, or commit messages.

## Feedback footprint

Per the [skill-triple pattern](https://github.com/BaseInfinity/xdlc/blob/main/docs/skill-triple-pattern.md),
the feedback skill writes **nothing in the consumer repo except an
append-only log file**. It never edits the case-study body, never
modifies setup-managed files. The only local write is to
`.opencode/feedback-log.md` (append-only) for traceability.

## Feedback types

### Bug report

1. Ask the user to describe the issue.
2. With permission, capture installed wizard version (from
   `.opencode/.wizard-stamp`).
3. With permission, capture which hooks are present and executable.
4. Open a GitHub issue with reproduction steps.

### Feature request

1. Ask what the user wants.
2. With permission, check whether a similar capability exists already.
3. Open a GitHub issue with the request and context.

### Pattern sharing

1. Ask what pattern the user has discovered (custom hook, modified
   plugin behavior, test approach).
2. With permission, diff the user's `.opencode/` against upstream
   defaults to identify customizations.
3. Ask: "Which of these customizations worked well for you?"
4. Open a GitHub issue describing the pattern with evidence.

### SDLC improvement

1. Ask what could be better about the workflow.
2. With permission, check which SDLC steps the user invokes most/least.
3. Open a GitHub issue with the improvement suggestion.

## Creating the issue

Use `gh issue create` against the wizard repo:

```bash
gh issue create \
  --repo BaseInfinity/opencode-sdlc-wizard \
  --title "[feedback-type]: Brief description" \
  --body "$(cat <<'EOF'
## Feedback Type
bug / feature / pattern / improvement

## Description
[User's description]

## Context
- Wizard version: [from .opencode/.wizard-stamp]
- OpenCode backend (if disclosed): [model id from opencode.json]
- Domain (if disclosed): firmware / data-science / CLI / web

## Evidence (if pattern sharing)
[What the user customized and why it worked]

---
Submitted via skill({ name: "feedback" })
EOF
)"
```

## Race-check discipline

Between "read context" (steps 1-3) and "open issue" (final step),
another skill (update) could have changed the wizard metadata. Compute
a small hash of `.opencode/.wizard-stamp` at the start of the flow,
re-read + re-compare before filing. Mismatch aborts filing; draft
fields are preserved in a transient file at `.opencode/feedback-draft.tmp`
for recovery. Lock-free optimistic concurrency.

## No credential handling

Delegate auth entirely to `gh` CLI. The skill never reads, stores, or
transmits tokens. Account-mismatch warning surfaces "you're authed as
X, filing to Y — continue?" so the user catches wrong-account mistakes
without any credential code in the skill.

## No local fallback

If upstream filing fails (permissions, archive, private), stop and
print the body for manual submission. Do not fall back to filing in
the consumer's own repo — that defeats the upstream-loop purpose.

## Rules

- **Privacy first** — always ask before scanning anything
- **Opt-in only** — if user declines scan, still create the issue with
  whatever they tell you manually
- **No source code** — never include source code snippets in issues
- **Be specific** — vague issues waste maintainer time; ask clarifying
  questions
- **Check duplicates** — `gh issue list --repo BaseInfinity/opencode-sdlc-wizard --search "keywords"` before creating

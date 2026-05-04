---
name: setup-wizard
description: Setup wizard for OpenCode SDLC — scans the repo, infers what it can, and only asks the user about unresolved preferences. Use for first-time setup or re-running setup.
---

# Setup Wizard

## Purpose

Confidence-driven setup wizard for OpenCode. Scan the project, infer as much
as possible, only ask about preferences or missing facts you genuinely
cannot resolve.

Do not ask a fixed checklist. Do not ask what you already know.

## Reasoning policy

Default to `xhigh` reasoning effort in this repo. Setup is one-time,
high-leverage work and deserves the strongest planning discipline.

## Scope guard

Setup owns repo metadata and OpenCode integration artifacts. It may create
or update setup-surface files such as:

- `AGENTS.md` (repo-root, OpenCode's primary instruction file)
- `TESTING.md` / `ARCHITECTURE.md` / `SDLC.md` (project docs)
- `.opencode/**` (plugins, hooks, skills, commands, settings)
- `opencode.json` (only with explicit user consent — see below)

During setup, do **not** edit application code, product logic, or
application tests. Verification is diagnostic by default: if tests or
validation fail outside setup-managed files, summarize the failures and
stop. Ask the user before switching from setup into implementation work,
or hand it off to `skill({ name: "sdlc" })`.

## Workflow

### Step 1 — Scan

Read what already exists:

- `AGENTS.md` — already present? note its scope.
- `CLAUDE.md` — present? OpenCode reads it as a fallback; we'll either
  consolidate into AGENTS.md or keep CLAUDE.md as a CC-specific file.
- `.opencode/` directory — wizard already installed? If yes, treat this
  as an update flow (suggest `skill({ name: "update-wizard" })` instead).
- `opencode.json` / `opencode.jsonc` — backend / model already pinned?
- `package.json` — pick up project name, version, bin entries.
- Test files (`*.test.*`, `tests/`, `__tests__/`) — what test runner?
- Workflow files (`.github/workflows/`) — does the repo run CI?

### Step 2 — Confirm preferences

Only ask about things you cannot infer:

1. **Backend.** "Which model backend? (anthropic / openai / ollama-local /
   azure / together / groq / openrouter / other)" — affects what we
   suggest in `opencode.json`'s `model` field. Default: leave existing
   value alone if `opencode.json` already pins one.
2. **Domain.** firmware / data-science / CLI / web — affects
   TESTING.md generation. Default: infer from package.json + repo
   structure if possible.
3. **Permissions strictness.** loose (auto-allow most tools) /
   moderate / strict (ask on every edit). Default: moderate.

### Step 3 — Generate

Based on Step 1 + 2 answers, generate or update:

- **AGENTS.md** at repo root with SDLC Baseline + skill catalog +
  domain-specific reminders. If AGENTS.md exists, surface a diff and
  let the user accept / reject per-section.
- **SDLC.md** with the wizard version stamp + recommended config table.
- **TESTING.md** with domain-appropriate testing diamond layers.
- **ARCHITECTURE.md** with project structure + deployment targets.

Run `bash install.sh` (or skip if user already ran it) to copy hooks,
plugin shim, and skills into `.opencode/`.

### Step 4 — Verify

Run `bash tests/test-bundle-integrity.sh` if it exists in the consumer
repo (only present if they cloned the wizard, not if they `npm` installed
it). Report any drift / missing files.

Tell the user how to use it:

> "Open OpenCode in this directory. AGENTS.md will auto-load. Run
> `skill({ name: "sdlc" })` to invoke the SDLC workflow on your next
> implementation task."

## What setup deliberately does NOT do

- **Does not pin a model in `opencode.json`** unless the user asks.
  OpenCode's auto-mode is preferred for most users; pinning a model
  disables auto-mode.
- **Does not enable any experimental OpenCode features** without user
  consent.
- **Does not write to `~/.config/opencode/`** (global config). Setup
  is project-scoped only.
- **Does not file feedback / open issues automatically.** That's
  `skill({ name: "feedback" })`'s job, with explicit consent.

## On re-run

Setup is idempotent. Re-running on an already-set-up repo should result
in zero edits unless the user explicitly asks to regenerate a specific
file. Always show a diff before overwriting any existing managed file.

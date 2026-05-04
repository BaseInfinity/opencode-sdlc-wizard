# OpenCode SDLC Wizard — Claude Instructions

> **Part of the [XDLC ecosystem](https://github.com/BaseInfinity/xdlc)** —
> sibling of `claude-sdlc-wizard`, `codex-sdlc-wizard`, `claude-gdlc-wizard`.
>
> **READ [`HANDOFF.md`](HANDOFF.md) FIRST.** It is the full bootstrap-session
> brain dump. Do not begin porting work without reading it — there are
> deferred design decisions, a research checklist, and an explicit order of
> operations.

## Project Overview

This is a **meta-repository in bootstrap stage** — empty except for handoff
docs. The previous (bootstrap) session created the repo + planning docs.
The next (implementation) session ports the wizard from
[`BaseInfinity/claude-sdlc-wizard`](https://github.com/BaseInfinity/claude-sdlc-wizard)
to OpenCode primitives, using
[`BaseInfinity/codex-sdlc-wizard`](https://github.com/BaseInfinity/codex-sdlc-wizard)
as the closest reference port.

### What this repo contains right now
- `HANDOFF.md` — the brain dump (read first)
- `README.md` — public-facing pitch + ecosystem table + status
- `CLAUDE.md` — this file
- `LICENSE` (MIT)
- `.gitignore`
- `package.json` (minimal, version `0.0.1`)

### What this repo will eventually contain (Phase A target)
- `hooks/` — 5 ported bash hooks (sdlc-prompt-check, tdd-pretool-check,
  instructions-loaded-check, model-effort-check, precompact-seam-check)
- `skills/` — 4 SKILL.md files (sdlc, setup, update, feedback) — verbatim from parent
- `cli/` — install/init scripts mirroring the Codex sibling pattern
- `install.sh` — one-shot non-destructive merge into a target repo's `.opencode/`
- `AGENTS.md` — agent-instruction file (verify OpenCode honors this — see HANDOFF research checklist)
- `tests/` — quality tests proving hooks fire under OpenCode
- `.github/workflows/` — CI + (optionally) upstream-sync from parent

## Commands

None yet. After Phase A:
| Command | Purpose |
|---------|---------|
| `npx opencode-sdlc-wizard init` | Install wizard into the current repo's `.opencode/` |
| `npx opencode-sdlc-wizard check` | Drift detection (mirror parent's check subcommand) |
| `bash tests/test-hooks.sh` | Verify hooks fire under OpenCode |

## Code Style

Match the sibling pattern. The parent and Codex sibling agree on:
- **Markdown:** ATX headers, tables for structured data, code fences with language hints
- **Bash:** `set -e`, quote variables, `$(command)` not backticks, `#!/usr/bin/env bash`
- **YAML (workflows):** 2-space indent, quote special-char strings, `|` for multi-line scripts

## Architecture (planned)

Same five-layer model as the parent wizard:
1. **Philosophy** — the master wizard doc (will be `OPENCODE_SDLC_WIZARD.md`)
2. **Enforcement** — hooks fire on every interaction
3. **Scoring** — multi-criteria SDLC compliance score (port from parent)
4. **Statistical validation** — score history + drift detection (Phase B)
5. **Self-improvement** — upstream sync from parent (optional, post-Phase-A)

## Git Workflow

- **Never commit directly to `main`** — use a feature branch and PR
- PRs require passing CI + cross-model review (Codex `xhigh`) before merge
- Match parent's "Roadmap is the priority queue" rhythm — pick next item from
  the parent repo's ROADMAP #9 phases, ship it, repeat

## Special Notes

- This is the **fourth** sibling in the family. The pattern is now well-trodden:
  - `claude-sdlc-wizard` was the original (full Claude Code adaptation)
  - `codex-sdlc-wizard` was the first port (proves the pattern is portable)
  - `claude-gdlc-wizard` was the first domain shift (games, not code)
  - `opencode-sdlc-wizard` is the second port (proves the pattern crosses
    agent runtimes, not just within Claude Code)
- Each sibling cross-references the others in its README (Ecosystem section).
  This repo's README already has it. After v0.1.0 ships, file mirror issues
  in the other 3 siblings to add OpenCode to their tables (parent repo
  already has examples — see `claude-sdlc-wizard` PR #300).

## Bootstrap Session Provenance

This repo was bootstrapped on **2026-05-03** by a Claude Code session
working in `BaseInfinity/claude-sdlc-wizard` after v1.64.0 shipped. The
maintainer explicitly authorized the spawn ("create the beginning of the
opencode port and then I'll have another claude code session finish it
off but dump all you need in there"). The bootstrap session's job was
exactly that: create the repo + handoff docs, then stop.

The implementation session is a fresh Claude Code session whose first
action should be reading `HANDOFF.md`.

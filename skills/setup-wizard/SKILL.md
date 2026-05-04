---
name: setup-wizard
description: Setup wizard for OpenCode SDLC — scans the repo, infers what it can, picks a backend by privacy tier, and writes opencode.json. Use for first-time setup or re-running setup.
---

# Setup Wizard

## Purpose

Confidence-driven setup wizard for OpenCode. Scan the project, infer as much
as possible, only ask about preferences or missing facts you genuinely
cannot resolve. Walk the user through backend selection by privacy tier and
write `opencode.json` for them.

Do not ask a fixed checklist. Do not ask what you already know.

## Reasoning policy

Default to `xhigh` reasoning effort in this repo. Setup is one-time,
high-leverage work and deserves the strongest planning discipline.

## Scope guard

Setup owns repo metadata and OpenCode integration artifacts. It may create
or update setup-surface files such as:

- `AGENTS.md` (repo-root, OpenCode's primary instruction file)
- `TESTING.md` / `ARCHITECTURE.md` / `SDLC.md` (project docs)
- `.opencode/**` (plugins, hooks, scripts, skills, commands, settings)
- `opencode.json` (only after the user picks a backend tier — see Step 3)

During setup, do **not** edit application code, product logic, or
application tests. Verification is diagnostic by default: if tests or
validation fail outside setup-managed files, summarize the failures and
stop. Ask the user before switching from setup into implementation work,
or hand it off to `skill({ name: "sdlc" })`.

## Workflow

### Step 1 — Scan the repo

Read what already exists:

- `AGENTS.md` — already present? note its scope.
- `CLAUDE.md` — present? OpenCode reads it as a fallback; consolidate into
  AGENTS.md or keep CLAUDE.md as a CC-specific file (dual-maintain is fine).
- `.opencode/` directory — wizard already installed? If yes, treat this
  as an update flow (suggest `skill({ name: "update-wizard" })` instead).
- `opencode.json` / `opencode.jsonc` — backend / model already pinned?
  If pinned, default to leaving it alone in Step 3 unless the user explicitly
  asks to switch.
- `package.json` — pick up project name, version, bin entries.
- Test files (`*.test.*`, `tests/`, `__tests__/`) — what test runner?
- Workflow files (`.github/workflows/`) — does the repo run CI?
- `PRIVACY.md` — already present? if so, skip the privacy-tier walkthrough
  and just confirm the user's preferred tier.

### Step 2 — Detect available backends

Run the detector to see what's reachable from this machine:

```bash
bash .opencode/scripts/detect-backends.sh
```

Output is JSON with four tiers (`private_local`, `enterprise`, `hosted_oss`,
`proprietary`) plus a `recommendation` string. The recommendation is
**privacy-first**: it picks the highest-privacy tier with a working backend,
not the highest model ceiling. Treat the recommendation as the default
suggestion in Step 3.

### Step 3 — Confirm preferences (only the things you cannot infer)

For each unresolved data point, ask once. Do not ask a fixed checklist.

1. **Backend tier + provider.** Use the detector output as the default.
   Present the tiers concisely with their privacy guarantee:

   - `private_local` — Ollama / LM Studio / llama.cpp / vLLM. Prompts never
     leave the machine. Recommended for privileged or regulated data.
   - `enterprise` — Azure OpenAI / AWS Bedrock / internal gateway. Stays in
     your tenant under contract.
   - `hosted_oss` — Together / Groq / OpenRouter. Open weights via a
     third-party host (their logging policy applies).
   - `proprietary` — Anthropic / OpenAI. Max capability; vendor-bound.

   Default the question to the detector's `recommendation`. If the user
   accepts, write `opencode.json` with:

   ```bash
   bash .opencode/scripts/configure-backend.sh \
        --tier <tier> --provider <provider> --model <model>
   ```

   For `private_local` runtimes, suggest `qwen2.5-coder:32b` (Ollama) or
   `deepseek-coder-v2:16b` as the model unless the user already pulled a
   different one. The configurator merges non-destructively; existing
   unrelated keys in `opencode.json` are preserved.

2. **Domain.** firmware / data-science / CLI / web — affects TESTING.md
   generation. Default: infer from package.json + repo structure if
   possible.

3. **Permissions strictness.** loose (auto-allow most tools) / moderate /
   strict (ask on every edit). Default: moderate.

### Step 4 — Generate

Based on Step 1 + 2 + 3 answers, generate or update:

- **AGENTS.md** at repo root with SDLC Baseline + skill catalog +
  domain-specific reminders. If AGENTS.md exists, surface a diff and
  let the user accept / reject per-section.
- **SDLC.md** with the wizard version stamp + recommended config table.
- **TESTING.md** with domain-appropriate testing diamond layers.
- **ARCHITECTURE.md** with project structure + deployment targets.
- **`opencode.json`** — already written in Step 3 if the user picked a
  backend. Otherwise, leave alone.

Run `bash install.sh` (or skip if user already ran it) to copy hooks,
plugin shim, and skills into `.opencode/`.

### Step 5 — Verify

Run `bash tests/test-bundle-integrity.sh` if it exists in the consumer
repo (only present if they cloned the wizard, not if they `npm` installed
it). Report any drift / missing files.

For `private_local` setups, also confirm the backend is reachable:

```bash
# Ollama: should return a JSON list of pulled models
curl -fsS http://localhost:11434/api/tags | head

# LM Studio / llama.cpp / vLLM: should return a /v1/models list
curl -fsS http://127.0.0.1:1234/v1/models   # adjust port per runtime
```

Tell the user how to use it:

> "Open OpenCode in this directory. AGENTS.md will auto-load. Run
> `skill({ name: "sdlc" })` to invoke the SDLC workflow on your next
> implementation task."

## What setup deliberately does NOT do

- **Does not pin a model in `opencode.json` without the user's explicit
  choice in Step 3.** OpenCode's auto-mode is preferred for users who
  haven't picked a tier; pinning a model disables auto-mode.
- **Does not write any API keys to disk.** All keys are referenced via
  `{env:VAR}` substitution. The user manages env vars themselves.
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

For backend re-selection, the configurator refuses to clobber an existing
`model` pin in `opencode.json` without `--force`. Surface this to the user
and wait for confirmation before passing `--force`.

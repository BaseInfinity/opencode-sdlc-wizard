## Preflight Self-Review: opencode-sdlc-wizard v0.1.0

- [x] All 3 test suites green (67/67 tests)
- [x] Bundle integrity: 5 hooks at top-level + .opencode/hooks/, no drift
- [x] Plugin shim parses as ESM, exports async function, uses portable
      `node:child_process` (works on Bun + Node)
- [x] Install behavior: idempotent, customization-preserving, --force opt-in
- [x] AGENTS.md replaces per-prompt SDLC BASELINE (OpenCode has no
      UserPromptSubmit analog)
- [x] Skills installed at `.opencode/skills/` (OpenCode-native), not parent's
      `.claude/skills/` location
- [x] `opencode.json` deliberately untouched in v0.1.0

### Concerns flagged for the reviewer

1. **OpenCode plugin event mapping is research-grade**, not battle-tested.
   The bootstrap session researched the events from public docs but did
   NOT run the wizard end-to-end against a live OpenCode install. The
   plugin works via `node --check` parse + bash syntax-check + glob-regex
   unit test, but the actual event contract from OpenCode (e.g., does
   `tool.execute.before` get `args.file_path` as expected, or does it
   require a different field name?) is unverified. **Reviewer:** check
   the plugin shim against current OpenCode plugin docs and flag any
   API drift.

2. **The TDD-pretool source-file filter** uses a hard-coded extension list
   (js/jsx/ts/.../py/go/rs/...). Unlike the parent wizard's `if:` field
   on the hook config (CC v2.1.85+), this filter lives in JS. If a user
   has unusual source extensions (e.g., Erlang `.erl`, Elixir `.ex`),
   the TDD nudge won't fire. Acceptable for v0.1.0, but reviewer should
   confirm the trade-off is intentional and documented.

3. **Skills are copied verbatim from claude-sdlc-wizard.** If the parent's
   skills mention Claude Code-specific commands (`/code-review`,
   `/sdlc`), those might confuse OpenCode users. The Codex sibling did
   not adapt them either, so we're following precedent — but reviewer
   should sample one or two skills to confirm they don't contain
   Claude-only references that would mislead OpenCode users.

4. **No `cli/init.js`** — install is bash-only. The parent wizard has
   a Node CLI for `npx agentic-sdlc-wizard init`. We deferred the
   Node CLI for v0.1.0 to keep scope tight; users run
   `bash <(curl ...)` or clone-and-install. Reviewer: is bash-only
   install acceptable for v0.1.0, or should we ship a thin Node CLI
   too (mostly so `npx opencode-sdlc-wizard init` works)?

5. **The plugin shim's stderr-channel choice for hook output.** I chose
   `process.stderr.write` rather than the OpenCode logger because plain
   stderr is the most reliable surface across Bun and Node runtimes.
   But OpenCode may have a structured logger via the `client` argument
   that would be friendlier. Acceptable for v0.1.0, but reviewer:
   recommend logger if it exists.

### Known limitations

- Phase B (backend matrix proof) and Phase C (hardware scout) are
  explicitly deferred to follow-up releases
- No upstream-sync workflow yet (the parent's pattern of
  `.github/workflows/upstream-sync.yml` from Codex sibling) — defer
  until the port stabilizes
- Cross-model review of every skill not done individually — they
  ship verbatim from the parent and the parent has its own review
  cadence

# Repository Guidelines

## Project Overview
Oriel is a local macOS companion for supervised AI browser work. It packages an
MIT-derived `ego-browser` runtime, connects it through a local daemon to a
Chromium browser selected by the user, and installs an `oriel-browser` skill for
Codex. It keeps login state inside the managed Chromium profile and does not
read, export, or print credentials.

This repo builds the Oriel app, its `oriel` CLI, local daemon, browser host
adapter, agent runtime, and skill packages. The CLI receives heredoc JavaScript
on stdin with the `nodejs` subcommand; `skills/oriel-browser/SKILL.md` is the
canonical Codex entry point.

## Architecture & Data Flow
- `package/ego-browser/src/index.ts` is the entrypoint with two startup paths:
  - Executed directly as a CLI → `runMain()` (reads JavaScript from stdin, executes it).
  - Imported as a module (how the app embeds it) → `installEgoSdk(globalThis)`.
- Both paths expose the same helper surface, built by `helperContext()` in `src/helpers.ts` — the single source of truth for what agents can call (including `help()` and `agent_helpers.js` extensions).
- `src/run.ts` executes stdin JavaScript inside an async function with the helpers injected as parameters.
- `src/browser-runtime.ts` owns CDP transport over `ego.sendCDPMessage`, session attach/caching (2s TTL, auto re-attach on session loss), the buffered event queue (10k cap), and JS dialog tracking.
- `src/cdp-eval.ts` provides `cdp()` and `js()` (string-expression evaluation; top-level `return` is auto-wrapped in an IIFE).
- `src/element-resolver.ts` resolves all target forms — `@N` refs, `loc=css:` / `loc=role:` / `loc=href:` locators, `xpath=`, raw CSS — and classifies failures as `transient` (retryable) or `permanent`.
- `src/ref-map.ts` + `src/ref-state.ts`: refs are numeric `backendNodeId`s (`@21`, not `@e21`). The map is rebuilt on every snapshot; using a ref while the map is empty triggers an automatic re-snapshot, which is what makes refs work across heredoc rounds.
- `src/driver/` — `nav` (tabs, navigation), `pointer` (click/scroll/drag), `keyboard`, `observe` (snapshot/screenshot), `waits`, `files` (upload), `element-ops` (objectId handles), `load`.
- `src/learning/` — discovery, validation, and execution of site skills from `skills/ego-browser/learnings/<site>/manifest.json` (`runSiteTool`, `runSiteBrowserTool`, `learnContext`).
- `src/state.ts` is the shared mutable runtime state singleton; `src/env.ts` resolves the agent workspace (`EGO_BROWSER_AGENT_WORKSPACE`, falling back to the skill dir bundled next to the build output, then the repo's `skills/ego-browser`).
- `src/help-runtime.ts` parses the built bundle's JSDoc with acorn at runtime to power `help()` — JSDoc on exported helpers is therefore user-facing documentation.

Data flow: `oriel nodejs` → `runMain()` → `helperContext()` helpers → private daemon RPC → Chromium CDP → snapshot or DOM/AX resolution → optional site tools → `console.log(...)`.

## Task Spaces
Task spaces are isolated browsing contexts with an ownership model (`agent` / `user`):
- `useOrCreateTaskSpace(nameOrId)` reuses an agent-owned space or creates a new one; it no longer auto-claims user-owned spaces. Use `claimTaskSpace(nameOrId)` to take ownership of a user-owned space. Ids are numeric; prefer `task.id` over names across rounds.
- `switchTaskSpace` requires agent ownership; `newTaskSpace` creates; `completeTaskSpace(nameOrId, { keep })` finishes (`keep` is mandatory).
- Control handoff: `handOffTaskSpace` / `takeOverTaskSpace` / `waitForAgentControl`.

## Key Directories
- `apps/macos/Sources/App/` — app lifecycle and scene entrypoints only.
- `apps/macos/Sources/Core/` — product state, domain models, local configuration, and localization access.
- `apps/macos/Sources/Features/` — browser control, Codex integration, diagnostics, control center, and onboarding.
- `apps/macos/Sources/Shared/` — reusable presentational components with no business actions.
- `apps/macos/Resources/` — localized English and Simplified Chinese product strings.
- `host-shim/` — CLI, daemon, RPC, runtime configuration, and CDP host adapter boundary.
- `package/ego-browser/src/` — runtime, helpers, resolver, drivers, learning subsystem.
- `package/ego-browser/src/**/*.test.mjs` — tests are colocated with the code (there is no separate `test/` directory).
- `package/ego-browser/scripts/` — runtime build, site-skill validation, and real-browser E2E cases.
- `skills/ego-browser/` — agent skill package: `SKILL.md` (canonical agent-facing usage guide), `references/install.md`, `scripts/install.sh`.
- `skills/ego-browser/learnings/` — reusable per-site experience packs (`manifest.json` + `notes/` + `tools/` + `browser-tools/`).
- `docs/ARCHITECTURE.md` — canonical product-level ownership, localization, and dependency map.

## Development Commands
Run from `package/ego-browser/`:
- `npm test` — build, typecheck, then `node --test` over `src/**/*.test.mjs`.
- `npm run e2e` — inherited ego-lite real-browser compatibility suite. It
  requires an ego-lite-compatible host and is not the Oriel product gate.
- `npm run verify:oriel-workflow` — packaged Oriel workflow smoke test: it
  launches an isolated temporary Chrome, opens a page, and proves a second CLI
  call reuses the same task space and page.
- `npm run validate:site-skills` (alias `validate:learnings`) — validate learned site skills.
- `~/.local/bin/oriel nodejs <<'JS' ... JS` — run through an installed Oriel browser connection. For a checkout, use `host-shim/oriel.mjs` with the bundled Node runtime after building the app.

## Code Conventions & Common Patterns
- ESM only (`"type": "module"`); Node 22+.
- Public helpers are camelCase, verb-first for async actions (`ensureSession`, `runSiteTool`).
- Time parameters are in seconds unless the name ends in `Ms`.
- Helpers are injected into the script scope, not imported by agent scripts.
- New public helpers go through `helperContext()` in `src/helpers.ts` and need JSDoc (it feeds `help()`); keep `SKILL.md` in sync.
- Snapshot refs (`@N`) are short-lived; re-snapshot after navigation or DOM changes and prefer stable `loc=...` values for reuse.
- Element-resolution failures should use `ElementResolutionError` with an honest `transient`/`permanent` kind — wait loops rely on it.
- The code prefers the small shared state singleton (`src/state.ts`) over threading connection state through call sites.
- Site skills must stay site-shaped and verifiable: stable URLs, durable selectors, no pixel coordinates, no secrets.

## Testing & QA
- Framework: Node's built-in runner (`node --test`), assertions via `node:assert/strict`.
- Tests run against the build output (`dist/src/...`) — `npm test` builds first.
- Behavior-focused tests inject overrides (`__testing.setOverrides`) or a `FakeEgo` double (see `src/helpers.test.mjs`, `src/taskspace-e2e.test.mjs`).
- Cover session handling, locator resolution, helper behavior, and site-skill validation when changing runtime code; run `npm run validate:site-skills` for learning changes.

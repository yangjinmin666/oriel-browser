# Contributing to Oriel

Oriel is a local macOS companion for supervised AI browser work. It bundles a
small Agent runtime and connects it to a Chrome, Tabbit, or Edge profile selected
by the user. Contributions should make that local workflow more reliable,
understandable, or safe; they should not add stealth automation, CAPTCHA
bypass, remote control, or credential extraction.

## Product Boundary

- macOS 13+ and Chromium-based Chrome, Tabbit, and Edge are supported today.
- Oriel launches a separate managed browser profile by default. It never copies
  or prints cookie values, passwords, tokens, or Keychain data.
- Browser control is deliberately local: the debugging endpoint and WebSocket
  must stay on loopback, and the daemon socket belongs to the current macOS
  user only.
- User-control hard stops are product behavior. Do not silently retry an action
  while the user holds a task space.

Safari, Firefox, cloud sync, automatic updates, Apple notarization, and
anti-bot bypass are not current contributions targets. See
[`docs/BETA_90_PLAN.md`](docs/BETA_90_PLAN.md) for the active Beta scope.

## Repository Map

```text
apps/macos/                 Native SwiftUI product shell
  Sources/App/              App lifecycle and window setup
  Sources/Core/             State, domain types, configuration, localization
  Sources/Features/         Browser control, Codex install, diagnostics, UI
host-shim/                  CLI, daemon, local RPC, CDP host adapter
package/ego-browser/src/    Agent runtime, helpers, driver, site learnings
skills/oriel-browser/       Codex entry-point skill
skills/ego-browser/         Runtime and reusable site knowledge
scripts/                    Architecture checks and macOS packaging
docs/                       Product architecture, Beta guide, execution log
```

The canonical ownership map is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Before adding a feature, place it
at the narrowest correct boundary:

| Change                                                 | Correct home                                         |
| ------------------------------------------------------ | ---------------------------------------------------- |
| Onboarding, setting, status, or recovery flow          | `apps/macos/Sources/Features/`                       |
| Shared app state, configuration, localization          | `apps/macos/Sources/Core/`                           |
| CLI, daemon, configuration validation, local RPC       | `host-shim/`                                         |
| Browser interaction such as click, drag, typing, waits | `package/ego-browser/src/driver/`                    |
| Public Agent helper surface                            | `package/ego-browser/src/helpers.ts` and `format.ts` |
| Site-specific selector or workflow knowledge           | `skills/ego-browser/learnings/<site>/`               |

## Development Setup

Requirements: macOS 13+, Xcode Command Line Tools, Node.js/npm. The app build
downloads and verifies its own pinned Node runtime, but npm is still needed for
runtime development.

```bash
npm --prefix package/ego-browser ci
./scripts/build-macos-app.sh
open build/Oriel.app
```

To exercise real browser behavior, use a disposable or Oriel-managed profile.
Do not point test automation at a user's daily browser profile, and never add
real account credentials to fixtures or test output.

## Verification

Run the smallest relevant check while iterating, then the complete gate before
sharing a build.

```bash
# Runtime and driver code
npm --prefix package/ego-browser test

# Site-learning changes
npm --prefix package/ego-browser run validate:site-skills

# Host shim, local RPC, and configuration
node --test host-shim/*.test.mjs

# Swift structure and localization keys
./scripts/check-architecture.sh

# Full package, DMG, signed local app, and packaged doctor check
./scripts/verify-beta.sh
```

Add a focused regression test for every behavior fix. Runtime tests import the
built `dist/src` files, so `npm test` always builds before it executes tests.
Browser-interaction changes should also receive a real Chromium case under
`package/ego-browser/scripts/real-browser-e2e/` when a mocked CDP assertion
cannot establish the behavior.

## Code and Documentation Rules

- Keep public helpers camelCase and document them with JSDoc; `help()` exposes
  that documentation to Agent users.
- Use the existing driver and locator helpers instead of introducing site logic
  into the local host adapter.
- Keep every visible Swift string behind an `L10n` key. English and Simplified
  Chinese resources must remain exactly in sync.
- Keep daemon RPC methods explicitly allowlisted and tested. Do not create a
  generic command tunnel from Agent code into the host.
- Avoid logging browser data. Cookie values, passwords, tokens, profiles, and
  Keychain material must neither appear in source, logs, fixtures, nor docs.
- Update [`README.md`](README.md), the relevant skill, and architecture docs
  whenever a user-facing workflow or boundary changes.

## Pull Requests

Use focused, conventional commit messages such as `fix: preserve HTML5 drag
data` or `docs: clarify local endpoint safety`. A pull request should explain:

1. The user-facing or reliability problem being solved.
2. The ownership boundary selected and why.
3. The exact verification commands run.
4. Any security, privacy, migration, or compatibility impact.

Before opening one, make sure `git diff --check` is clean and the full Beta gate
passes for changes that affect packaging, host integration, or public behavior.

## Version Tags and Builds

Oriel release tags use the product-specific `oriel-v<version>` form, where the
version must match the `VERSION` value exactly. For example,
`VERSION=0.2.0-alpha` is tagged as `oriel-v0.2.0-alpha`. Plain `v*` tags in the
repository belong to the imported upstream history and must not trigger an
Oriel package or Release.

The macOS workflow builds and uploads a CI artifact for an Oriel tag, but it
does not publish a GitHub Release. Public Releases remain a deliberate
maintainer action until Developer ID signing, notarization, and the clean-user
acceptance procedure are complete.

## License and Upstream Notice

Oriel includes a runtime derived from
[CitroLabs/ego-lite](https://github.com/citrolabs/ego-lite), licensed under
MIT. Preserve the notices in [`LICENSE`](LICENSE) and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) when distributing builds or
substantial portions of the runtime.

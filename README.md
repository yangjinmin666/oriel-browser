# Ego Anywhere

Use Codex with the Chromium browser you already prefer.

Ego Anywhere packages the MIT-licensed `ego-browser` runtime with a lightweight
macOS control center. It detects Chrome, Tabbit, and Edge, launches a managed
browser with a persistent local profile, and installs the Codex skill and CLI
without requiring terminal setup or a separate AI browser.

> **Status:** `v0.1.0-alpha`. The core runtime is well tested, but the macOS app
> is an early preview and is not yet notarized.

## What works

- Native macOS control center and menu-bar status
- Automatic Chrome, Tabbit, and Edge detection
- One-click managed browser startup on a localhost-only CDP endpoint
- Persistent browser login state without copying or exporting cookies
- One-click Codex CLI and skill installation
- Semantic snapshots, refs, navigation, clicks, typing, screenshots, waits, and
  task spaces from the upstream runtime
- Site notes for GitHub, Zhihu, BOSS Zhipin, and other tested workflows

Chrome and Tabbit have both passed an end-to-end packaged-runtime check.
The runtime test suite currently contains 299 passing tests.

## How it works

```mermaid
flowchart LR
    A["Codex"] --> B["ego-anywhere CLI"]
    B --> C["MIT ego-browser runtime"]
    C --> D["Local CDP host"]
    D --> E["Chrome / Tabbit / Edge"]
    F["macOS control center"] --> D
    F --> G["Browser profile and settings"]
```

The managed browser uses its own profile under:

```text
~/Library/Application Support/Ego Anywhere/
```

Log in normally inside that browser once. Chromium stores and encrypts the
login state. Ego Anywhere does not print, export, or copy cookie values.

## Build the macOS app

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- npm

```bash
./scripts/build-macos-app.sh
```

The app is written to:

```text
build/Ego Anywhere.app
```

Build a local DMG:

```bash
./scripts/package-macos-dmg.sh
```

The build downloads a pinned official Node.js runtime, verifies its SHA-256
checksum, and bundles it in the app. End users do not need Node.js installed.

## First run

1. Open **Ego Anywhere**.
2. Select Chrome, Tabbit, or Edge.
3. Press **Start browser**.
4. Log in to any websites you want to use.
5. Press **One-click install** under Codex integration.
6. Restart Codex.

After that, Codex can run:

```bash
ego-anywhere --doctor
```

and browser tasks through the installed `ego-anywhere` skill.

## Security model

- The debugging endpoint is bound to `127.0.0.1`.
- While the managed browser is running, any process on the same Mac may be able
  to control it. Stop the browser from the control center when it is not needed.
- Browser credentials are not printed or committed to this repository.
- CAPTCHA and platform security challenges must be completed by the user.
- Site automation must respect platform rules. Ego Anywhere does not promise
  that bulk messaging, purchases, applications, or other consequential actions
  will pass anti-abuse systems.

## Development

Runtime tests:

```bash
cd package/ego-browser
npm test
npm run validate:site-skills
```

Host configuration tests:

```bash
node --test host-shim/runtime-config.test.mjs
```

## Roadmap

- First-run onboarding polish and accessibility review
- Signed and notarized Apple Silicon and Intel DMGs
- Automatic updates
- Optional connection to an existing browser session
- Windows packaging
- More tested site packs

## Upstream and license

This repository is derived from
[CitroLabs/ego-lite](https://github.com/citrolabs/ego-lite). Its open-source
`ego-browser` runtime is used under the MIT License. The original CitroLabs
copyright and license notice are preserved.

See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

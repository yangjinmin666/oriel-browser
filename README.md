# Oriel

**AI 浏览器协作台。让 Codex 使用你选择的 Chromium 浏览器。**

Oriel packages the MIT-licensed `ego-browser` runtime with a lightweight
macOS control center. It detects Chrome, Tabbit, and Edge, launches a managed
browser with a persistent local profile, and installs the Codex skill and CLI
without requiring terminal setup or a separate AI browser.

> **Status:** `v0.2.0-alpha` Beta. The core runtime and local packaging gate are
> tested; the macOS app is not yet notarized for public distribution.

## What works

- Native macOS control center and menu-bar status
- Automatic Chrome, Tabbit, and Edge detection, including user-level
  `~/Applications` installs
- One-click managed browser startup on a verified localhost-only Chromium CDP endpoint
- Persistent browser login state without copying or exporting cookies
- Persistent local daemon that reuses task spaces and pages across Codex calls
- One-click Codex CLI and skill installation
- Semantic snapshots, refs, navigation, clicks, typing, screenshots, waits,
  HTML5 drag-and-drop, and task spaces from the upstream runtime
- Site notes for GitHub, Zhihu, BOSS Zhipin, and other tested workflows

The packaged Oriel runtime has an end-to-end check that starts an isolated
temporary Chrome profile, opens a page, and proves two independent CLI calls
reuse the same task and page before reading semantic snapshots. Chrome and
Tabbit have also been manually exercised through the macOS control center.
The runtime test suite currently contains 303 passing tests, plus 25 host and
daemon protocol tests.

## How it works

```mermaid
flowchart LR
    A["Codex"] --> B["oriel CLI"]
    B --> C["MIT ego-browser runtime"]
    C --> D["Private Unix socket"]
    D --> E["Persistent Oriel daemon"]
    E --> F["Local CDP host"]
    F --> G["Chrome / Tabbit / Edge"]
    H["macOS control center"] --> F
    H --> I["Browser profile and settings"]
```

The complete ownership map and dependency rules are documented in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

The managed browser uses its own profile under:

```text
~/Library/Application Support/Oriel/
```

Log in normally inside that browser once. Chromium stores and encrypts the
login state. Oriel does not print, export, or copy cookie values.

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
build/Oriel.app
```

Build a local DMG:

```bash
./scripts/package-macos-dmg.sh
```

The build downloads a pinned official Node.js runtime, verifies its SHA-256
checksum, and bundles it in the app. End users do not need Node.js installed.

## Opening a distributed DMG on macOS

**This build is not yet Developer ID signed or notarized.** The current DMG is
ad-hoc signed for local integrity checks only, and macOS Gatekeeper rejects it
on a normal first launch. This is a known Beta limitation, not an install error.

For a copy you obtained from the DMG, the actual first-open flow is:

1. Drag `Oriel.app` to `Applications` and double-click it once.
2. macOS shows a security warning such as “Apple cannot check this app for
   malicious software” or that the developer cannot be verified. The exact
   words follow your macOS language and version. Choose **Done** or **Cancel**;
   it does not open at this point.
3. Open **System Settings -> Privacy & Security**, scroll to **Security**, and
   choose **Open Anyway** for Oriel. This option normally remains for about an
   hour after the blocked launch.
4. Confirm **Open** in the second warning. macOS may ask for the current
   macOS account password before it opens.

That is three confirmations after the first double-click: dismiss the blocked
launch, **Open Anyway**, then **Open** (plus a password when macOS asks). After
that, macOS records the exception and later double-clicks open normally. Do not
override this warning unless the DMG came from a source you trust. Apple’s
current guidance is [here](https://support.apple.com/en-us/102445).

## First run after Oriel opens

1. Open **Oriel**.
2. Select Chrome, Tabbit, or Edge.
3. Press **Start browser**.
4. Log in to any websites you want to use.
5. Press **One-click install** under Codex integration.
6. Restart Codex.

After that, Codex can run:

```bash
oriel --doctor
```

and browser tasks through the installed `oriel-browser` skill. The legacy
`zhiyou` and `ego-anywhere` commands remain available as compatibility aliases.

Inspect or stop the persistent background process:

```bash
oriel --daemon-status
oriel --daemon-stop
```

For the full first-run, privacy, status, and troubleshooting guide, read
[`docs/BETA_GUIDE.md`](docs/BETA_GUIDE.md).

## Security model

- The debugging endpoint is bound to `127.0.0.1`; Oriel verifies its Chromium
  DevTools response and loopback WebSocket before connecting or stopping it.
- Daemon RPC uses a user-only Unix socket with `0600` permissions.
- While the managed browser is running, any process on the same Mac may be able
  to control it. Stop the browser from the control center when it is not needed.
- Browser credentials are not printed or committed to this repository.
- CAPTCHA and platform security challenges must be completed by the user.
- Site automation must respect platform rules. Oriel does not promise
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
node --test host-shim/*.test.mjs
```

Run the complete local Beta verification before sharing a DMG:

```bash
./scripts/verify-beta.sh
```

The verification script checks the build, packaged Oriel browser workflow,
app signature, embedded resources, DMG contents, tests, and public-release
safety guard. It does not claim Apple Developer signing or notarization.

The true clean-account acceptance record, including what remains blocked until
an administrator creates a new macOS user, is in
[`docs/CLEAN_ENVIRONMENT_ACCEPTANCE.md`](docs/CLEAN_ENVIRONMENT_ACCEPTANCE.md).

## Roadmap

- One-button onboarding and clearer daemon diagnostics
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

# Oriel Beta Guide

Oriel is a local macOS companion that lets Codex work through a browser you
choose. It is designed for deliberate, supervised work: you stay responsible
for logging in, reviewing consequential actions, and completing any website
security challenge.

## Start in five steps

1. Open Oriel and choose Chrome, Tabbit, or Edge.
2. Select **Start**. Oriel opens a separate, managed browser profile.
3. Log in to the sites you want to use in that browser.
4. In **Codex**, select **Install** once, then reopen Codex.
5. Ask Codex to use the `oriel-browser` skill for browser tasks.

The browser profile stays on your Mac at
`~/Library/Application Support/Oriel/`. It is separate from your everyday
browser profile, so signing in there does not alter your existing browser
window or its tabs.

## First launch from the DMG

This Beta is ad-hoc signed for local integrity verification but is **not
notarized by Apple**. On an ordinary macOS account, Gatekeeper blocks the first
launch. This is expected for the current Beta:

1. Drag Oriel into `Applications` and double-click it once.
2. A macOS warning says that Apple cannot check the app for malicious software,
   or that its developer cannot be verified. Wording varies by macOS release
   and language. Choose **Done** or **Cancel**.
3. Go to **System Settings -> Privacy & Security**, scroll to **Security**, and
   select **Open Anyway** for Oriel. The control is normally available for
   about one hour after the failed open.
4. Confirm **Open** in the next warning. macOS may ask for the current account
   password.

This is three confirmations after the initial double-click: dismiss, **Open
Anyway**, then **Open**. Later launches should open normally because macOS
remembers the exception. Only override Gatekeeper for a DMG you trust. See
[Apple’s guidance](https://support.apple.com/en-us/102445) for the current
system behavior.

## What the status means

| Status | Meaning | What to do |
| --- | --- | --- |
| Browser connection: Ready | The managed browser is ready for Codex. | Keep it open while Codex is working. |
| Browser connection: Needs attention | No Oriel-managed browser is running. | Select a detected browser and choose **Start**. |
| Background service | The local helper starts only when Codex first needs it. | No action is needed when it says it will start with the first task. |
| Local configuration: Needs attention | The local connection settings need repair. | Choose **Repair local connection**. It does not remove browser data or sign-ins. |

Use the stethoscope button in the lower right to run a full preflight check.

## Privacy and safety

- Oriel binds browser debugging to `127.0.0.1`, verifies that the endpoint is
  real Chromium DevTools, and only follows a loopback WebSocket. It is never
  exposed to the network.
- Oriel does not print, export, upload, or copy browser cookie values.
- Its local background service uses a socket accessible only to your macOS
  user account.
- Any program running as your macOS user can potentially control an Oriel
  browser while it is open. Stop the browser from Oriel when you finish.
- Oriel does not solve CAPTCHAs, platform risk checks, or login verification.
  Complete those yourself in the managed browser.
- Do not ask Oriel to send bulk messages, buy products, submit applications,
  or perform another consequential action without reviewing the final action.

## Beta limits

This Beta supports Chromium-based Chrome, Tabbit, and Edge on macOS 13 or
newer. It does not support Safari, Firefox, cloud sync, remote browser control,
automatic updates, or Apple-notarized public distribution yet.

The clean-environment acceptance status and the exact remaining test steps are
recorded in [`CLEAN_ENVIRONMENT_ACCEPTANCE.md`](CLEAN_ENVIRONMENT_ACCEPTANCE.md).

## Before reporting a problem

1. Stop the managed browser and start it again from Oriel.
2. Run the preflight check.
3. If local configuration needs repair, use **Repair local connection**.
4. Send the Oriel version, macOS version, browser choice, and a redacted
   screenshot of the status area.

Never include passwords, cookies, copied terminal output containing credentials,
or a browser profile folder in a report.

## Maintainer verification

Run the complete local Beta gate before sharing a build:

```bash
./scripts/verify-beta.sh
```

It checks the runtime tests, host tests, a packaged Oriel workflow (open a page
and read a snapshot across two independent CLI calls), localized macOS app,
self-signature, packaged assets, and DMG contents. Apple Developer signing and
notarization are separate release prerequisites; this script intentionally
cannot claim either.

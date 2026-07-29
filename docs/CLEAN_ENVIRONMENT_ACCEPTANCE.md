# Oriel Clean-Environment Acceptance

Date: 2026-07-30
Status: **BLOCKED — not a passing acceptance result**

## Acceptance rule

The only valid acceptance is a different, freshly created macOS user account.
That user may receive only the Oriel DMG and this repository’s README. It must
not use the development checkout, inherited configuration, custom environment
variables, a pre-existing Oriel profile, or a pre-installed Oriel skill.

The test ends only when Codex invokes Oriel once, opens a page, and receives a
semantic snapshot. Every prompt and deviation must be recorded here.

## What was actually checked before the clean account

| Check | Actual result |
| --- | --- |
| Current app signature | Ad-hoc signature; no Developer Team identifier. |
| Gatekeeper assessment | `spctl --assess --type execute` returned `rejected`. This is expected for the unnotarized Beta. |
| Packaged product workflow | Passed three consecutive times using `build/Oriel.app`, a temporary Oriel configuration, and an isolated temporary Chrome profile. Each run opened a local fixture, took a semantic snapshot, then used a second independent CLI process to reuse the exact same task and page and take another snapshot. |
| Existing user browser | Not touched. The workflow test neither connects to Tabbit nor opens, closes, or reads an existing browser profile. |
| New macOS user | Not created. This machine has no cached non-interactive administrator authorization, and creating a user requires the local account owner’s macOS password. |

## Why a fake home directory does not count

An attempted test with a temporary `HOME` directory was rejected as evidence.
It does not provide a functioning macOS login Keychain. Chromium then exhibits
non-representative state: a created target can report its real URL while a CDP
page session still observes `about:blank`. That would hide a real first-run
problem instead of testing it. Oriel’s packaged workflow keeps the real macOS
home for Keychain integration while isolating Oriel configuration and the
Chrome profile in temporary paths.

## Exact remaining procedure on a fresh macOS user

1. An administrator creates a new standard macOS user, then logs into that
   user’s desktop. Record macOS version and whether Chrome, Tabbit, or Edge is
   present before doing anything else.
2. Copy only `Oriel-<version>.dmg` and `README.md` into that user’s Downloads
   folder. Do not copy the project directory, `~/.codex`, an Oriel profile, or
   any shell configuration.
3. Mount the DMG, drag Oriel to `Applications`, then double-click it. Record
   every system prompt verbatim enough to identify it, including Gatekeeper and
   any request for an administrator or login password.
4. If Gatekeeper blocks it, use exactly the README instructions: dismiss the
   first warning, open **System Settings -> Privacy & Security -> Open Anyway**,
   then confirm **Open**. Record whether the button appears and how many
   confirmations or password prompts macOS actually requires.
5. Follow the README’s five first-run steps. If no supported Chromium browser
   is installed, record that as a blocker; do not install one silently. If one
   is installed, start it through Oriel and record the first-run result.
6. Open the already-installed Codex desktop app for that new user. Use Oriel’s
   one-click Codex installation, restart Codex, and ask it to open a harmless
   public page such as `https://example.com` through `oriel-browser`.
7. Pass only if Codex reports the page title/content from a semantic snapshot.
   Record the browser selected, Oriel version, result of `oriel --doctor`, and
   every manual action required. Never include passwords, cookies, account
   names, browser profile files, or Keychain contents.

## Known user-visible first-launch warning

Because this release is neither Developer ID signed nor notarized, a normal
first open is expected to show an Apple security alert. Apple documents the
generic sequence as: after the failed open, go to **Privacy & Security**, click
**Open Anyway**, then confirm **Open**. The label and initial button text vary
by macOS version and language; a current system can show “Apple cannot check
this app for malicious software” with **Done** and **Move to Trash**, or an
unidentified-developer variant. The override may require the current macOS
account password.

This is a distribution blocker for a frictionless public launch. Notarization
and Developer ID signing are needed before Oriel can honestly claim a
no-warning installation experience. Apple’s current documentation:
[Safely open apps on your Mac](https://support.apple.com/en-us/102445).

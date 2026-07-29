# Oriel Beta Execution Log

Date: 2026-07-30

## Summary

Oriel is ready for a small, supervised macOS Beta under the scope in
[`BETA_90_PLAN.md`](BETA_90_PLAN.md). The product remains intentionally outside
the scope of Safari/Firefox support, cloud features, automatic updates, Apple
Developer signing, and notarization.

## Completed work

| Area | Result | Commit |
| --- | --- | --- |
| Runtime configuration and diagnostics | Strict localhost-only validation, structured safe doctor output, and 20 host tests. | `574bc54` |
| macOS recovery | Individual health status, duplicate-start prevention, and non-destructive local connection repair. | `b64c22a` |
| Packaging and user guidance | Single version source, repeatable app/DMG verification, CI gate, release safety check, and Beta guide. | `4a1ae00` |
| Final package exercise | The verification gate also runs the packaged doctor from the built app and from the mounted DMG. | `4ee1e7c` |
| Active-session reliability repair | Restored the bundled Node lookup, made the hidden-title-bar window movable, and brings a minimized control center back on launch or from the menu. | This commit |
| Interaction and connection hardening | Added real Chromium HTML5 drag-and-drop with a compatible fallback, verified every browser endpoint as loopback Chromium DevTools, and removed the runtime's static module cycle. | Pending final validation commit |
| Packaged workflow and active-page reliability | Packaged app opens a page, snapshots it, and a second independent CLI call reuses the same task and page. Explicit tab activation now updates the host’s selected-page state before CDP dispatch. | Pending final validation commit |

## Automated verification passed

```text
./scripts/verify-beta.sh
```

The command passed with:

- architecture and bilingual localization checks;
- public-release secret and browser-data guard;
- 25 host and daemon tests;
- 303 runtime tests plus TypeScript typecheck;
- site-skill validation;
- signed app validation and required-resource checks;
- matching app/DMG version metadata;
- DMG checksum, mounted contents, and packaged runtime doctor checks.

## Active-session check

The control center was opened in an active macOS session on 2026-07-29. It
rendered normally and correctly reported a running, Oriel-managed Tabbit as
connected. The repair also enables standard macOS background dragging for the
hidden-title-bar window and restores the window when it was minimized.

The window's drag implementation is covered by the native AppKit configuration.
Browser-content dragging is additionally covered by a real Chromium regression:
it validates ordinary pointer movement and an HTML5 `DataTransfer` drop event.

An unrelated `Proof Safe Storage` Keychain prompt appeared during the visual
check. It belonged to the separate Proof application, not Oriel; no Keychain
access was granted or requested by Oriel.

## Still required before public distribution

- Apple Developer ID signing.
- Apple notarization and stapling.
- A clean-install and workflow test on at least one additional Mac.
- A decided update-distribution channel.

No daily browser was launched, closed, or modified during this verification.

## Clean-environment acceptance

Status: **blocked, not passed**. A true new macOS user is required to prove the
DMG and README work without a development tree or pre-existing configuration.
The current shell has no non-interactive administrator authorization, so it
cannot create or enter that account without the account owner approving a
macOS password prompt. The record deliberately does not substitute a fake
`HOME` directory: Chromium relies on the real macOS Keychain and that simulation
produces an invalid browser state rather than an honest new-user result.

The detailed checklist, actual Gatekeeper observation, and remaining actions
are in [`CLEAN_ENVIRONMENT_ACCEPTANCE.md`](CLEAN_ENVIRONMENT_ACCEPTANCE.md).

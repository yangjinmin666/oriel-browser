# Oriel Beta Execution Log

Date: 2026-07-29

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

## Automated verification passed

```text
./scripts/verify-beta.sh
```

The command passed with:

- architecture and bilingual localization checks;
- public-release secret and browser-data guard;
- 20 host and daemon tests;
- 299 runtime tests plus TypeScript typecheck;
- site-skill validation;
- signed app validation and required-resource checks;
- matching app/DMG version metadata;
- DMG checksum, mounted contents, and packaged runtime doctor checks.

## Active-session check

The control center was opened in an active macOS session on 2026-07-29. It
rendered normally and correctly reported a running, Oriel-managed Tabbit as
connected. The repair also enables standard macOS background dragging for the
hidden-title-bar window and restores the window when it was minimized.

The window's drag implementation is covered by the native AppKit configuration;
the final physical pointer-drag confirmation remains a short interactive Beta
check because it cannot be established from a screenshot alone.

An unrelated `Proof Safe Storage` Keychain prompt appeared during the visual
check. It belonged to the separate Proof application, not Oriel; no Keychain
access was granted or requested by Oriel.

## Still required before public distribution

- Apple Developer ID signing.
- Apple notarization and stapling.
- A clean-install and workflow test on at least one additional Mac.
- A decided update-distribution channel.

No daily browser was launched, closed, or modified during this verification.

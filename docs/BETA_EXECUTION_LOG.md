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
| Final package exercise | The verification gate also runs the packaged doctor from the built app and from the mounted DMG. | Pending this log's commit |

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

## Manual follow-up after the Mac is active

Open `build/Oriel-0.2.0-alpha.dmg`, drag Oriel to Applications, then open it.
Confirm the control center renders and that **Start**, **Install**, and
**Repair local connection** are visible. The automated run was performed while
the display was inactive; its black screenshot is not treated as graphical
evidence.

## Still required before public distribution

- Apple Developer ID signing.
- Apple notarization and stapling.
- A clean-install and workflow test on at least one additional Mac.
- A decided update-distribution channel.

No daily browser was launched, closed, or modified during this verification.

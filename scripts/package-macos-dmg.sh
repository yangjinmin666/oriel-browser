#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Ego Anywhere.app"
DMG="$ROOT/build/Ego-Anywhere-0.1.0-alpha.dmg"
STAGING="$(mktemp -d "$ROOT/build/dmg-root.XXXXXX")"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-macos-app.sh"
fi

cp -R "$APP" "$STAGING/Ego Anywhere.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Ego Anywhere" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

echo "$DMG"

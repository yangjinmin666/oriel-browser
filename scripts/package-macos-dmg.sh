#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/智游 ZhiYou.app"
DMG="$ROOT/build/ZhiYou-0.1.0-alpha.dmg"
LEGACY_DMG="$ROOT/build/Ego-Anywhere-0.1.0-alpha.dmg"
STAGING="$(mktemp -d "$ROOT/build/dmg-root.XXXXXX")"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-macos-app.sh"
fi

rm -f "$LEGACY_DMG"
cp -R "$APP" "$STAGING/智游 ZhiYou.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "智游 ZhiYou" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

echo "$DMG"

#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/read-version.sh"
APP="$ROOT/build/Oriel.app"
DMG="$ROOT/build/Oriel-${VERSION}.dmg"
LEGACY_DMG="$ROOT/build/Ego-Anywhere-0.1.0-alpha.dmg"
PREVIOUS_DMGS=(
  "$ROOT/build/ZhiYou-0.1.0-alpha.dmg"
  "$ROOT/build/ZhiYou-0.2.0-alpha.dmg"
)
STAGING="$(mktemp -d "$ROOT/build/dmg-root.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-macos-app.sh"
fi

rm -f "$LEGACY_DMG" "${PREVIOUS_DMGS[@]}"
cp -R "$APP" "$STAGING/Oriel.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Oriel" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

echo "$DMG"

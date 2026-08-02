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

# `hdiutil -srcfolder` can underestimate filesystem overhead on a clean GitHub
# macOS runner and create a volume that fills while copying the bundled Node
# runtime. Size the image from the staged payload with explicit headroom.
STAGING_KB="$(du -sk "$STAGING" | awk '{print $1}')"
IMAGE_KB=$((STAGING_KB * 2 + 65536))

hdiutil create \
  -volname "Oriel" \
  -srcfolder "$STAGING" \
  -size "${IMAGE_KB}k" \
  -fs HFS+ \
  -ov \
  -format UDZO \
  "$DMG"

echo "$DMG"

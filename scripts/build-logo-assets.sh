#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/Oriel.iconset"
RENDERER="$ROOT/scripts/render-svg.swift"
APP_ICON="$ROOT/assets/oriel-app-icon.svg"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

swift "$RENDERER" "$ROOT/assets/oriel-logo.svg" 1024 "$ROOT/assets/oriel-logo.png"

for pair in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  size="${pair%% *}"
  name="${pair#* }"
  swift "$RENDERER" "$APP_ICON" "$size" "$ICONSET/$name"
done

iconutil -c icns "$ICONSET" -o "$ROOT/assets/Oriel.icns"
rm -rf "$ICONSET"

echo "$ROOT/assets/Oriel.icns"

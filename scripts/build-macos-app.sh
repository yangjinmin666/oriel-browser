#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/read-version.sh"
APP="$ROOT/build/Oriel.app"
LEGACY_APP="$ROOT/build/智游 ZhiYou.app"
OLDER_LEGACY_APP="$ROOT/build/Ego Anywhere.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
RUNTIME="$RESOURCES/Runtime"
NODE_VERSION="${NODE_VERSION:-v22.23.1}"
MACHINE_ARCH="$(uname -m)"

case "$MACHINE_ARCH" in
  arm64)
    NODE_ARCH="arm64"
    SWIFT_ARCH="arm64"
    ;;
  x86_64)
    NODE_ARCH="x64"
    SWIFT_ARCH="x86_64"
    ;;
  *)
    echo "Unsupported macOS architecture: $MACHINE_ARCH" >&2
    exit 1
    ;;
esac

NODE_ARCHIVE="node-${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_CACHE="$ROOT/build/cache/$NODE_ARCHIVE"
NODE_DIR="$ROOT/build/cache/node-${NODE_VERSION}-darwin-${NODE_ARCH}"

"$ROOT/scripts/check-architecture.sh"

cd "$ROOT/package/ego-browser"
npm run build

mkdir -p "$ROOT/build/cache"
if [[ ! -x "$NODE_DIR/bin/node" ]]; then
  EXPECTED_SHA="$(
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" |
      awk -v archive="$NODE_ARCHIVE" '$2 == archive { print $1 }'
  )"
  if [[ -z "$EXPECTED_SHA" ]]; then
    echo "Node checksum not found for $NODE_ARCHIVE" >&2
    exit 1
  fi
  curl -fL --retry 3 -o "$NODE_CACHE" "$NODE_URL"
  ACTUAL_SHA="$(shasum -a 256 "$NODE_CACHE" | awk '{ print $1 }')"
  if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "Node checksum mismatch for $NODE_ARCHIVE" >&2
    exit 1
  fi
  tar -xzf "$NODE_CACHE" -C "$ROOT/build/cache"
fi

rm -rf "$APP" "$LEGACY_APP" "$OLDER_LEGACY_APP"
mkdir -p "$MACOS" "$RUNTIME/bin" "$RUNTIME/browser-runtime" \
  "$RUNTIME/skill" "$RESOURCES/Skill" "$RESOURCES/ThirdParty" "$RESOURCES/Fonts"

SWIFT_SOURCES=("$ROOT"/apps/macos/Sources/**/*.swift(N))
if (( ${#SWIFT_SOURCES[@]} == 0 )); then
  echo "No Swift sources found under apps/macos/Sources" >&2
  exit 1
fi

swiftc \
  -parse-as-library \
  -O \
  -target "${SWIFT_ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS/Oriel" \
  "${SWIFT_SOURCES[@]}"

cp "$ROOT/apps/macos/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :OrielReleaseLabel string $VERSION" "$CONTENTS/Info.plist"
cp "$ROOT/assets/Oriel.icns" "$RESOURCES/Oriel.icns"
cp "$ROOT/assets/oriel-logo.svg" "$RESOURCES/OrielLogo.svg"
cp "$ROOT/assets/fonts/SpaceGrotesk-Variable.ttf" "$RESOURCES/Fonts/SpaceGrotesk-Variable.ttf"
for localization in "$ROOT"/apps/macos/Resources/*.lproj(N); do
  cp -R "$localization" "$RESOURCES/"
done
cp "$NODE_DIR/bin/node" "$RUNTIME/bin/node"
cp "$ROOT/host-shim/oriel.mjs" "$RUNTIME/oriel.mjs"
cp "$ROOT/host-shim/oriel-daemon.mjs" "$RUNTIME/oriel-daemon.mjs"
cp "$ROOT/host-shim/daemon-rpc.mjs" "$RUNTIME/daemon-rpc.mjs"
cp "$ROOT/host-shim/debug-endpoint.mjs" "$RUNTIME/debug-endpoint.mjs"
cp "$ROOT/host-shim/runtime-config.mjs" "$RUNTIME/runtime-config.mjs"
cp "$ROOT/host-shim/stock-chrome-host.mjs" "$RUNTIME/stock-chrome-host.mjs"
cp -R "$ROOT/package/ego-browser/dist/src/." "$RUNTIME/browser-runtime/"
cp -R "$ROOT/skills/ego-browser/." "$RUNTIME/skill/"
cp -R "$ROOT/skills/oriel-browser" "$RESOURCES/Skill/oriel-browser"
cp "$ROOT/LICENSE" "$RESOURCES/ThirdParty/ego-lite-LICENSE"
cp "$NODE_DIR/LICENSE" "$RESOURCES/ThirdParty/Node-LICENSE"
cp "$ROOT/assets/fonts/SpaceGrotesk-OFL.txt" "$RESOURCES/ThirdParty/SpaceGrotesk-OFL.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/ThirdParty/THIRD_PARTY_NOTICES.md"

chmod 755 "$MACOS/Oriel" "$RUNTIME/bin/node" \
  "$RUNTIME/oriel.mjs" "$RUNTIME/oriel-daemon.mjs"
codesign --force --deep --sign - "$APP"

echo "$APP"

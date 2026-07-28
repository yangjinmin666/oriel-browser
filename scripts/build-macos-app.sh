#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/智游 ZhiYou.app"
LEGACY_APP="$ROOT/build/Ego Anywhere.app"
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

rm -rf "$APP" "$LEGACY_APP"
mkdir -p "$MACOS" "$RUNTIME/bin" "$RUNTIME/browser-runtime" \
  "$RUNTIME/skill" "$RESOURCES/Skill" "$RESOURCES/ThirdParty"

swiftc \
  -parse-as-library \
  -O \
  -target "${SWIFT_ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS/ZhiYou" \
  "$ROOT/apps/macos/Sources/ZhiYouApp.swift"

cp "$ROOT/apps/macos/Info.plist" "$CONTENTS/Info.plist"
cp "$NODE_DIR/bin/node" "$RUNTIME/bin/node"
cp "$ROOT/host-shim/zhiyou.mjs" "$RUNTIME/zhiyou.mjs"
cp "$ROOT/host-shim/runtime-config.mjs" "$RUNTIME/runtime-config.mjs"
cp "$ROOT/host-shim/stock-chrome-host.mjs" "$RUNTIME/stock-chrome-host.mjs"
cp -R "$ROOT/package/ego-browser/dist/src/." "$RUNTIME/browser-runtime/"
cp -R "$ROOT/skills/ego-browser/." "$RUNTIME/skill/"
cp -R "$ROOT/skills/zhiyou-browser" "$RESOURCES/Skill/zhiyou-browser"
cp "$ROOT/LICENSE" "$RESOURCES/ThirdParty/ego-lite-LICENSE"
cp "$NODE_DIR/LICENSE" "$RESOURCES/ThirdParty/Node-LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/ThirdParty/THIRD_PARTY_NOTICES.md"

chmod 755 "$MACOS/ZhiYou" "$RUNTIME/bin/node" "$RUNTIME/zhiyou.mjs"
codesign --force --deep --sign - "$APP"

echo "$APP"

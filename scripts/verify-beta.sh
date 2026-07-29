#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/read-version.sh"
APP="$ROOT/build/Oriel.app"
DMG="$ROOT/build/Oriel-${VERSION}.dmg"

"$ROOT/scripts/check-architecture.sh"
"$ROOT/scripts/check-public-release.sh"
node --test "$ROOT"/host-shim/*.test.mjs
npm --prefix "$ROOT/package/ego-browser" test
npm --prefix "$ROOT/package/ego-browser" run validate:site-skills
"$ROOT/scripts/build-macos-app.sh"

codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
APP_RELEASE_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :OrielReleaseLabel' "$APP/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$MARKETING_VERSION" || "$APP_BUILD" != "$BUILD_NUMBER" || "$APP_RELEASE_LABEL" != "$VERSION" ]]; then
  echo "Bundled version does not match VERSION." >&2
  exit 1
fi

required_bundle_files=(
  "Contents/MacOS/Oriel"
  "Contents/Resources/Oriel.icns"
  "Contents/Resources/OrielLogo.svg"
  "Contents/Resources/Runtime/bin/node"
  "Contents/Resources/Runtime/oriel.mjs"
  "Contents/Resources/Runtime/oriel-daemon.mjs"
  "Contents/Resources/Runtime/runtime-config.mjs"
  "Contents/Resources/Skill/oriel-browser/SKILL.md"
  "Contents/Resources/en.lproj/Localizable.strings"
  "Contents/Resources/zh-Hans.lproj/Localizable.strings"
  "Contents/Resources/ThirdParty/THIRD_PARTY_NOTICES.md"
)

for bundle_file in "${required_bundle_files[@]}"; do
  if [[ ! -e "$APP/$bundle_file" ]]; then
    echo "Missing required app resource: $bundle_file" >&2
    exit 1
  fi
done

"$ROOT/scripts/package-macos-dmg.sh"
hdiutil verify "$DMG" >/dev/null

MOUNT_POINT="$(mktemp -d "$ROOT/build/oriel-dmg.XXXXXX")"
DEVICE=""
cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  rm -rf "$MOUNT_POINT"
}
trap cleanup EXIT

DEVICE="$(hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" | awk '/\/dev\/disk/ { print $1; exit }')"
if [[ ! -d "$MOUNT_POINT/Oriel.app" || ! -L "$MOUNT_POINT/Applications" ]]; then
  echo "DMG contents are incomplete." >&2
  exit 1
fi

echo "Oriel Beta verification passed: $VERSION (build $BUILD_NUMBER)."

#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="$ROOT/apps/macos/Sources"
RESOURCE_ROOT="$ROOT/apps/macos/Resources"
ORIEL_SKILL="$ROOT/skills/oriel-browser/SKILL.md"

for directory in App Core Features Shared; do
  if [[ ! -d "$SOURCE_ROOT/$directory" ]]; then
    echo "Missing macOS architecture directory: $directory" >&2
    exit 1
  fi
done

ROOT_SWIFT_FILES=("$SOURCE_ROOT"/*.swift(N))
if (( ${#ROOT_SWIFT_FILES[@]} != 0 )); then
  echo "Swift files must live in a functional directory, not Sources/:" >&2
  printf '  %s\n' "${ROOT_SWIFT_FILES[@]}" >&2
  exit 1
fi

SWIFT_FILES=("$SOURCE_ROOT"/**/*.swift(N))
ENTRYPOINTS=()
for source in "${SWIFT_FILES[@]}"; do
  if grep -q '^@main$' "$source"; then
    ENTRYPOINTS+=("$source")
  fi
done

EXPECTED_ENTRYPOINT="$SOURCE_ROOT/App/OrielApp.swift"
if (( ${#ENTRYPOINTS[@]} != 1 )) || [[ "${ENTRYPOINTS[1]:-}" != "$EXPECTED_ENTRYPOINT" ]]; then
  echo "The only macOS @main entrypoint must be App/OrielApp.swift." >&2
  exit 1
fi

if grep -R -n '^import SwiftUI$' "$SOURCE_ROOT/Core" >/dev/null; then
  echo "Core must not depend on SwiftUI views." >&2
  exit 1
fi

LOCALIZATION_FILES=(
  "$RESOURCE_ROOT/en.lproj/Localizable.strings"
  "$RESOURCE_ROOT/zh-Hans.lproj/Localizable.strings"
)
for localization in "${LOCALIZATION_FILES[@]}"; do
  plutil -lint "$localization" >/dev/null
done

TEMP_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT

extract_localization_keys() {
  sed -nE 's/^"([^"]+)"[[:space:]]*=.*/\1/p' "$1" | sort -u
}

extract_localization_keys "${LOCALIZATION_FILES[1]}" > "$TEMP_DIRECTORY/en.keys"
extract_localization_keys "${LOCALIZATION_FILES[2]}" > "$TEMP_DIRECTORY/zh-Hans.keys"

if ! cmp -s "$TEMP_DIRECTORY/en.keys" "$TEMP_DIRECTORY/zh-Hans.keys"; then
  echo "English and Simplified Chinese localization keys differ:" >&2
  diff -u "$TEMP_DIRECTORY/en.keys" "$TEMP_DIRECTORY/zh-Hans.keys" >&2 || true
  exit 1
fi

perl -0777 -ne '
  while (/L10n\.(?:text|format)\(\s*"([^"]+)"/g) {
    print "$1\n";
  }
' "${SWIFT_FILES[@]}" | sort -u > "$TEMP_DIRECTORY/source.keys"

if ! comm -23 "$TEMP_DIRECTORY/source.keys" "$TEMP_DIRECTORY/en.keys" \
  > "$TEMP_DIRECTORY/missing.keys"; then
  exit 1
fi
if [[ -s "$TEMP_DIRECTORY/missing.keys" ]]; then
  echo "Localization keys used by Swift but missing from resources:" >&2
  sed 's/^/  /' "$TEMP_DIRECTORY/missing.keys" >&2
  exit 1
fi

if ! comm -13 "$TEMP_DIRECTORY/source.keys" "$TEMP_DIRECTORY/en.keys" \
  > "$TEMP_DIRECTORY/unused.keys"; then
  exit 1
fi
if [[ -s "$TEMP_DIRECTORY/unused.keys" ]]; then
  echo "Localization keys declared but unused by Swift:" >&2
  sed 's/^/  /' "$TEMP_DIRECTORY/unused.keys" >&2
  exit 1
fi

if [[ ! -f "$ORIEL_SKILL" ]]; then
  echo "Missing Oriel agent skill: $ORIEL_SKILL" >&2
  exit 1
fi

for obsolete_api in "useOrCreateTaskSpace(" "snapshotText("; do
  if grep -Fq "$obsolete_api" "$ORIEL_SKILL"; then
    echo "Oriel skill still teaches obsolete API: $obsolete_api" >&2
    exit 1
  fi
done

for current_api in \
  "taskSpaces.useOrCreate(" \
  "browser.openOrReuseTab(" \
  "page.snapshot("; do
  if ! grep -Fq "$current_api" "$ORIEL_SKILL"; then
    echo "Oriel skill is missing current API guidance: $current_api" >&2
    exit 1
  fi
done

for historical_skill in ego-anywhere zhiyou-browser; do
  if [[ -e "$ROOT/skills/$historical_skill" ]]; then
    echo "Historical skill residue must be removed: skills/$historical_skill" >&2
    exit 1
  fi
done

if grep -n "ego-anywhere\\|Ego Anywhere" \
  "$ROOT/README.md" "$SOURCE_ROOT/Core/Domain.swift" >/dev/null; then
  echo "Removed ego-anywhere branding remains in README.md or Domain.swift." >&2
  exit 1
fi

for agent_root in ".codex/skills" ".claude/skills"; do
  if ! grep -Fq "\"$agent_root\"" "$SOURCE_ROOT/Core/Domain.swift"; then
    echo "Agent integration is missing install root: $agent_root" >&2
    exit 1
  fi
done

echo "Architecture and localization checks passed."

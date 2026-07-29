#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing VERSION file." >&2
  exit 1
fi

VERSION="$(sed -nE 's/^VERSION=([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?)$/\1/p' "$VERSION_FILE")"
BUILD_NUMBER="$(sed -nE 's/^BUILD_NUMBER=([0-9]+)$/\1/p' "$VERSION_FILE")"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "VERSION must define a semantic VERSION and numeric BUILD_NUMBER." >&2
  exit 1
fi

MARKETING_VERSION="${VERSION%%-*}"

export VERSION BUILD_NUMBER MARKETING_VERSION

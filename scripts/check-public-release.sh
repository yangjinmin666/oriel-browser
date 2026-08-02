#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

blocked_paths=()
while IFS= read -r tracked_file; do
  case "$tracked_file" in
    .env|.env.*|*.pem|*.key|*.p12|*.mobileprovision|*"/Cookies"|*"/Cookies-journal"|*"/Login Data"|*"/config.json"|*"/Profile"/*)
      blocked_paths+=("$tracked_file")
      ;;
  esac
done < <(git ls-files)

if (( ${#blocked_paths[@]} > 0 )); then
  echo "Tracked files include local credentials or browser data:" >&2
  printf '  %s\n' "${blocked_paths[@]}" >&2
  exit 1
fi

token_files="$(git grep -I -l -E '(ghp_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16})' || true)"
if [[ -n "$token_files" ]]; then
  echo "Tracked files contain token-like material:" >&2
  printf '%s\n' "$token_files" | sed 's/^/  /' >&2
  exit 1
fi

for required_pattern in \
  'Library/Application Support/Oriel/' \
  'build/' \
  '.env' \
  '*.p12' \
  '*.mobileprovision'; do
  if ! grep -Fqx "$required_pattern" .gitignore; then
    echo ".gitignore is missing required protection: $required_pattern" >&2
    exit 1
  fi
done

CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
MACOS_WORKFLOW="$ROOT/.github/workflows/macos-app.yml"

if grep -R -n -E 'title="ego lite|ego-browser-\$\{version_tag\}|gh release (create|edit|upload)' \
  "$ROOT/.github/workflows" >/dev/null; then
  echo "GitHub workflows still contain the inherited ego-lite release path." >&2
  exit 1
fi

if ! grep -Fq 'node --test host-shim/*.test.mjs' "$CI_WORKFLOW"; then
  echo "CI must run the host-shim test suite." >&2
  exit 1
fi

if grep -Fq -- '- "v*"' "$MACOS_WORKFLOW"; then
  echo "macOS packaging must not react to inherited upstream v* tags." >&2
  exit 1
fi

if ! grep -Fq -- '- "oriel-v*"' "$MACOS_WORKFLOW"; then
  echo "macOS packaging must use Oriel-namespaced release tags." >&2
  exit 1
fi

echo "Public release check passed."

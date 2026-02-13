#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH="${1:-}"
if [[ -z "$ZIP_PATH" ]]; then
  echo "Usage: $0 <bootstrap-zip>" >&2
  exit 1
fi
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "ERROR: file not found: $ZIP_PATH" >&2
  exit 1
fi

entries="$(unzip -Z1 "$ZIP_PATH")"

has_line() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -qx "$pattern" <<<"$entries"
  else
    grep -Fxq "$pattern" <<<"$entries"
  fi
}

has_legacy_termux_path() {
  local content="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -q '/data/data/com\.termux' <<<"$content"
  else
    grep -Eq '/data/data/com\.termux' <<<"$content"
  fi
}

need_entry() {
  local e="$1"
  if ! has_line "$e"; then
    echo "ERROR: missing entry: $e" >&2
    return 1
  fi
  return 0
}

echo "== Audit bootstrap =="
echo "file: $ZIP_PATH"

need_entry "bin/pkg"
need_entry "etc/apt/sources.list"
need_entry "etc/profile"

if ! has_line "bin/adb"; then
  echo "ERROR: missing bin/adb" >&2
  exit 1
fi

declare -a files=(
  "bin/pkg"
  "bin/termux-change-repo"
  "bin/termux-info"
  "bin/termux-reset"
  "bin/login"
  "etc/profile"
  "etc/termux-login.sh"
  "etc/profile.d/init-termux-properties.sh"
  "etc/motd.sh"
)

legacy_hits=0
for f in "${files[@]}"; do
  if ! has_line "$f"; then
    continue
  fi
  content="$(unzip -p "$ZIP_PATH" "$f" 2>/dev/null || true)"
  if has_legacy_termux_path "$content"; then
    echo "ERROR: legacy com.termux path found in $f" >&2
    legacy_hits=$((legacy_hits + 1))
  fi
done

if [[ "$legacy_hits" -gt 0 ]]; then
  echo "ERROR: found $legacy_hits files with legacy com.termux path" >&2
  exit 1
fi

echo "OK: bootstrap audit passed"

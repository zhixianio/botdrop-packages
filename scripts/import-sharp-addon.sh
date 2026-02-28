#!/usr/bin/env bash
##
## Import a pre-built sharp-node-addon .deb into local debs-output directory
## for repo generation.
##
## Usage:
##   ./scripts/import-sharp-addon.sh <sharp-node-addon.deb | url> [debs-output-dir]
##
## Examples:
##   ./scripts/import-sharp-addon.sh /tmp/sharp-node-addon_0.34.5_aarch64.deb ./debs-output
##   ./scripts/import-sharp-addon.sh https://example.com/sharp-node-addon_0.34.5_aarch64.deb ./debs-output

set -euo pipefail

SHARP_ADDON_SOURCE="${1:-}"
DEBS_OUTPUT_DIR="${2:-./debs-output}"

if [ -z "$SHARP_ADDON_SOURCE" ]; then
  echo "Usage: $0 <sharp-node-addon.deb|url> [debs-output-dir]"
  exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "❌ dpkg-deb is required but not found"
  exit 1
fi

tmp_file=""
cleanup() {
  if [ -n "${tmp_file:-}" ] && [ -f "$tmp_file" ]; then
    rm -f "$tmp_file"
  fi
}
trap cleanup EXIT

if [[ "$SHARP_ADDON_SOURCE" =~ ^https?:// ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "❌ curl is required to download remote .deb"
    exit 1
  fi
  tmp_file="$(mktemp)"
  echo "🌐 Downloading sharp addon: $SHARP_ADDON_SOURCE"
  if ! curl -fsSL "$SHARP_ADDON_SOURCE" -o "$tmp_file"; then
    echo "❌ Failed to download addon deb"
    exit 1
  fi
  SHARP_ADDON_DEB="$tmp_file"
else
  SHARP_ADDON_DEB="$SHARP_ADDON_SOURCE"
fi

if [ ! -f "$SHARP_ADDON_DEB" ]; then
  echo "❌ File not found: $SHARP_ADDON_DEB"
  exit 1
fi

PKG_NAME="$(dpkg-deb -f "$SHARP_ADDON_DEB" Package 2>/dev/null || true)"
PKG_ARCH="$(dpkg-deb -f "$SHARP_ADDON_DEB" Architecture 2>/dev/null || true)"
PKG_VER="$(dpkg-deb -f "$SHARP_ADDON_DEB" Version 2>/dev/null || true)"
PKG_DEPS="$(dpkg-deb -f "$SHARP_ADDON_DEB" Depends 2>/dev/null || true)"

if [ "$PKG_NAME" != "sharp-node-addon" ]; then
  echo "❌ Invalid package: expected sharp-node-addon, got ${PKG_NAME:-<unknown>}"
  exit 1
fi

if [ "$PKG_ARCH" != "aarch64" ]; then
  echo "❌ Invalid architecture: expected aarch64, got ${PKG_ARCH:-<unknown>}"
  exit 1
fi

for dep in libvips glib libarchive; do
  if ! grep -qw "$dep" <<<"${PKG_DEPS}"; then
    echo "❌ sharp-node-addon dependency check failed, missing: $dep"
    exit 1
  fi
done

mkdir -p "$DEBS_OUTPUT_DIR"
cp "$SHARP_ADDON_DEB" "$DEBS_OUTPUT_DIR/"

echo "✅ Imported sharp-node-addon_${PKG_VER}_aarch64.deb to $DEBS_OUTPUT_DIR/"

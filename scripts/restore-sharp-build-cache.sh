#!/bin/bash
##
## Restore cached .deb packages into the Termux build prefix.
##
## This enables incremental CI builds by restoring previously built packages
## so the Termux build system's "skip if already built" mechanism kicks in.
##
## Usage:
##   ./scripts/restore-sharp-build-cache.sh [debs-dir] [arch]
##

set -euo pipefail

DEBS_DIR="${1:-./output}"
ARCH="${2:-aarch64}"
BUILT_PACKAGES_DIR="/data/data/.built-packages"

if [ ! -d "$DEBS_DIR" ]; then
    echo "No cache directory found ($DEBS_DIR), skipping restore."
    exit 0
fi

deb_count=$(find "$DEBS_DIR" -maxdepth 1 -name '*.deb' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$deb_count" -eq 0 ]; then
    echo "No cached .deb files found, starting fresh build."
    exit 0
fi

echo "========================================="
echo "  Restoring $deb_count cached packages"
echo "========================================="

mkdir -p "$BUILT_PACKAGES_DIR"
restored=0
failed=0

for deb in "$DEBS_DIR"/*.deb; do
    [ -f "$deb" ] || continue

    pkg_name=$(dpkg-deb -f "$deb" Package 2>/dev/null) || continue
    pkg_version=$(dpkg-deb -f "$deb" Version 2>/dev/null) || continue

    if [ -z "$pkg_name" ] || [ -z "$pkg_version" ]; then
        continue
    fi

    # Extract package files into prefix.
    # Use --exclude='.' to skip the root directory entry and avoid
    # "Cannot utime/change mode" errors on /.
    if ar p "$deb" data.tar.xz 2>/dev/null | tar xJ -C / --exclude='.' 2>/dev/null; then
        echo "$pkg_version" > "$BUILT_PACKAGES_DIR/$pkg_name"
        restored=$((restored + 1))
    else
        echo "  Warning: failed to extract $pkg_name, will rebuild"
        failed=$((failed + 1))
    fi
done

echo ""
echo "Restored $restored packages ($failed failed)"
echo "========================================="

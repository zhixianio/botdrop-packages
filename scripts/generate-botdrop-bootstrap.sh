#!/usr/bin/env bash
##
##  Generate BotDrop bootstrap archives using pre-built packages from
##  the Termux apt repository. Much faster than build-botdrop-bootstrap.sh
##  which compiles everything from source (~3h vs ~5min).
##
##  Usage:
##    ./scripts/generate-botdrop-bootstrap.sh [--architectures aarch64]
##

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# BotDrop additional packages to include in the bootstrap.
BOTDROP_PACKAGES=(
    "nodejs-lts"      # Node.js LTS runtime
    "npm"             # npm package manager
    "git"             # Git version control
    "openssh"         # SSH client and server
    "openssl"         # OpenSSL tools
    "termux-api"      # Termux:API interface
    "proot"           # proot for /tmp support via termux-chroot
    "expect"          # expect for automated password setup
    "android-tools"   # adb/fastboot for wireless ADB fallback
)

# Convert array to comma-separated list
BOTDROP_PACKAGES_CSV=$(IFS=,; echo "${BOTDROP_PACKAGES[*]}")

echo "========================================"
echo "  BotDrop Bootstrap Generator (fast mode)"
echo "========================================"
echo ""
echo "Additional packages to include:"
for pkg in "${BOTDROP_PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""
echo "Using pre-built packages from Termux apt repo"
echo "========================================"

# Run generate-bootstraps.sh with BotDrop packages.
exec "${SCRIPT_DIR}/generate-bootstraps.sh" \
    --add "${BOTDROP_PACKAGES_CSV}" \
    "$@"

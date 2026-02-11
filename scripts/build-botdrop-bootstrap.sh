#!/usr/bin/env bash
##
##  Script for building BotDrop custom bootstrap archives.
##
##  This is a wrapper around build-bootstraps.sh that adds BotDrop-specific
##  packages to the bootstrap.
##
##  Usage:
##    ./scripts/run-docker.sh ./scripts/build-botdrop-bootstrap.sh [options]
##
##  Options are passed through to build-bootstraps.sh
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
echo "  BotDrop Bootstrap Builder"
echo "========================================"
echo ""
echo "Additional packages to include:"
for pkg in "${BOTDROP_PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""
echo "========================================"

# Run the standard build-bootstraps.sh with BotDrop packages added.
exec "${SCRIPT_DIR}/build-bootstraps.sh" \
    --add "${BOTDROP_PACKAGES_CSV}" \
    "$@"

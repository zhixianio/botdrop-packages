#!/usr/bin/env bash
##
##  Generate Owlia bootstrap archives using pre-built packages from
##  the Termux apt repository. Much faster than build-owlia-bootstrap.sh
##  which compiles everything from source (~3h vs ~5min).
##
##  Usage:
##    ./scripts/generate-owlia-bootstrap.sh [--architectures aarch64]
##

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Owlia additional packages to include in the bootstrap
OWLIA_PACKAGES=(
    "nodejs-lts"      # Node.js LTS runtime
    "npm"             # npm package manager (separate package in Termux)
    "git"             # Git version control
    "openssh"         # SSH client and server
    "openssl"         # OpenSSL tools
    "termux-api"      # Termux:API interface
    "proot"           # proot for /tmp support via termux-chroot
    "expect"          # expect for automated password setup
)

# Convert array to comma-separated list
OWLIA_PACKAGES_CSV=$(IFS=,; echo "${OWLIA_PACKAGES[*]}")

echo "========================================"
echo "  Owlia Bootstrap Generator (fast mode)"
echo "========================================"
echo ""
echo "Additional packages to include:"
for pkg in "${OWLIA_PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""
echo "Using pre-built packages from Termux apt repo"
echo "========================================"

# Run the generate-bootstraps.sh with Owlia packages
exec "${SCRIPT_DIR}/generate-bootstraps.sh" \
    --add "${OWLIA_PACKAGES_CSV}" \
    "$@"

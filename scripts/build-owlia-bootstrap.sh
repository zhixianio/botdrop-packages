#!/usr/bin/env bash
##
##  Script for building Owlia custom bootstrap archives.
##
##  This is a wrapper around build-bootstraps.sh that adds Owlia-specific
##  packages to the bootstrap.
##
##  Usage:
##    ./scripts/run-docker.sh ./scripts/build-owlia-bootstrap.sh [options]
##
##  Options are passed through to build-bootstraps.sh
##

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"

# Owlia additional packages to include in the bootstrap
# These packages will be pre-installed in the bootstrap archive
OWLIA_PACKAGES=(
    "nodejs-lts"      # Node.js LTS runtime (~50MB)
    "npm"             # npm package manager (separate in Termux)
    "git"             # Git version control (~15MB)
    "openssh"         # SSH client and server (~5MB)
    "openssl"         # OpenSSL tools (~5MB)
    "termux-api"      # Termux:API interface (~1MB)
    "proot"           # proot for /tmp support via termux-chroot (~2MB)
)

# Convert array to comma-separated list
OWLIA_PACKAGES_CSV=$(IFS=,; echo "${OWLIA_PACKAGES[*]}")

echo "========================================"
echo "  Owlia Bootstrap Builder"
echo "========================================"
echo ""
echo "Additional packages to include:"
for pkg in "${OWLIA_PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""
echo "========================================"

# Run the standard build-bootstraps.sh with Owlia packages added
exec "${SCRIPT_DIR}/build-bootstraps.sh" \
    --add "${OWLIA_PACKAGES_CSV}" \
    "$@"

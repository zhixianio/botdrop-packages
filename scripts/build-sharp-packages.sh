#!/bin/bash
##
## Script for building all sharp dependencies for BotDrop.
##
## This builds 33 packages required for Node.js sharp library:
## - libvips (core image processing library)
## - 26 libvips dependencies (image format libraries, graphics libs)
## - 6 build tools (needed when npm builds sharp from source)
##
## Usage:
##   ./scripts/build-sharp-packages.sh [arch] [output-dir]
##
## Arguments:
##   arch        Target architecture (default: aarch64)
##   output-dir  Directory to collect built .deb files (default: ./debs-output)
##

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Package list in dependency order
# Build tools must come first as they're needed to compile other packages
SHARP_PACKAGES=(
    # Build tools (required when npm builds sharp from source)
    "pkg-config"
    "ndk-sysroot"
    "python"
    "make"
    "binutils-is-llvm"
    "which"

    # Core dependencies (no dependencies themselves)
    "zlib"
    "libexpat"

    # Level 1 dependencies
    "cgif"
    "fftw"
    "fontconfig"
    "glib"
    "imath"
    "libjpeg-turbo"
    "libpng"
    "libexif"
    "libimagequant"
    "littlecms"

    # Level 2 dependencies
    "libwebp"
    "libtiff"
    "libheif"
    "libjxl"
    "openexr"
    "openjpeg"

    # X11 dependencies
    "xorgproto"
    "libxrender"

    # Higher level libraries
    "libcairo"
    "pango"
    "librsvg"
    "poppler"
    "imagemagick"
    "libarchive"

    # The main package
    "libvips"
)

ARCH="${1:-aarch64}"
OUTPUT_DIR="${2:-./debs-output}"

echo "========================================"
echo "  BotDrop Sharp Packages Builder"
echo "========================================"
echo ""
echo "Architecture:    $ARCH"
echo "Output directory: $OUTPUT_DIR"
echo "Package count:    ${#SHARP_PACKAGES[@]}"
echo ""
echo "========================================"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Track success/failure
declare -a BUILT_PACKAGES=()
declare -a FAILED_PACKAGES=()
declare -a SKIPPED_PACKAGES=()

# Build each package
for pkg in "${SHARP_PACKAGES[@]}"; do
    echo ""
    echo "[$(date '+%H:%M:%S')] Building: $pkg"
    echo "----------------------------------------"

    cd "$REPO_ROOT"

    if ./build-package.sh -a "$ARCH" "$pkg" 2>&1 | tee "/tmp/build-${pkg}.log"; then
        echo "  ✅ Build succeeded: $pkg"

        # Copy generated .deb files to output directory
        # Look in both output/ and debs/ directories
        deb_count=0
        for deb_dir in output debs; do
            if [ -d "$deb_dir" ]; then
                while IFS= read -r -d '' deb_file; do
                    cp "$deb_file" "$OUTPUT_DIR/"
                    echo "     Copied: $(basename "$deb_file")"
                    deb_count=$((deb_count + 1))
                done < <(find "$deb_dir" -name "${pkg}_*.deb" -print0 2>/dev/null)
            fi
        done

        if [ $deb_count -gt 0 ]; then
            BUILT_PACKAGES+=("$pkg")
        else
            echo "  ⚠️  No .deb found for $pkg (might be a dependency that was already built)"
            SKIPPED_PACKAGES+=("$pkg")
        fi
    else
        # Check if it's a "no build.sh" error (dependency package)
        if grep -q "No build.sh script at package dir" "/tmp/build-${pkg}.log" 2>/dev/null; then
            echo "  ⚠️  Skipped: $pkg (dependency package, no build.sh)"
            SKIPPED_PACKAGES+=("$pkg")
        else
            echo "  ❌ Build failed: $pkg"
            FAILED_PACKAGES+=("$pkg")

            # Show last 20 lines of error log
            echo "  Error log (last 20 lines):"
            tail -20 "/tmp/build-${pkg}.log" | sed 's/^/    /'
        fi
    fi
done

echo ""
echo "========================================"
echo "  Build Summary"
echo "========================================"
echo ""
echo "✅ Successfully built:  ${#BUILT_PACKAGES[@]} packages"
if [ ${#BUILT_PACKAGES[@]} -gt 0 ]; then
    printf '   - %s\n' "${BUILT_PACKAGES[@]}"
fi
echo ""

if [ ${#SKIPPED_PACKAGES[@]} -gt 0 ]; then
    echo "⚠️  Skipped:            ${#SKIPPED_PACKAGES[@]} packages"
    printf '   - %s\n' "${SKIPPED_PACKAGES[@]}"
    echo ""
fi

if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    echo "❌ Failed:             ${#FAILED_PACKAGES[@]} packages"
    printf '   - %s\n' "${FAILED_PACKAGES[@]}"
    echo ""
fi

echo "📦 Total .deb files:    $(ls -1 "$OUTPUT_DIR"/*.deb 2>/dev/null | wc -l | tr -d ' ')"
echo "💾 Output directory:    $OUTPUT_DIR"
echo ""
echo "========================================"

# Exit with error if critical packages failed
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Some packages failed to build. Check logs above."
    exit 1
fi

echo ""
echo "✅ Build process completed successfully!"
echo ""
echo "Next step: Create APT repository with:"
echo "  ./scripts/create-botdrop-repo.sh $OUTPUT_DIR ./botdrop-repo $ARCH"

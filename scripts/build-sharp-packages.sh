#!/bin/bash
##
## Script for building all sharp dependencies for BotDrop.
##
## This builds 65 packages required for Node.js sharp library:
## - libvips (core image processing library)
## - 58 libvips dependencies (image format libraries, graphics libs)
## - 6 build tools (needed when npm builds sharp from source)
##
## Usage:
##   ./scripts/build-sharp-packages.sh [arch] [output-dir]
##
## Arguments:
##   arch        Target architecture (default: aarch64)
##   output-dir  Directory to collect built .deb files (default: ./debs-output)
##

set -eo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Package list in dependency order
# Build tools must come first as they're needed to compile other packages
SHARP_PACKAGES=(
    # ── Build tools (required when npm builds sharp from source) ──
    "pkg-config"
    "ndk-sysroot"
    "make"
    "binutils-is-llvm"
    "which"

    # ── Tier 0: Zero-dependency foundation packages ──
    "cgif"
    "fftw"
    "zlib"
    "libpng"                  # depends: zlib
    "libexpat"
    "giflib"                  # NEW
    "libandroid-execinfo"     # NEW
    "libandroid-shmem"        # NEW
    "liblzo"                  # NEW
    "libpixman"               # NEW
    "libaom"                  # NEW
    "libdav1d"                # NEW
    "libnspr"                 # NEW
    "librav1e"                # NEW (Rust/Cargo build)
    "imath"                   # depends: libc++

    # ── Tier 1: Depend on bootstrap or Tier 0 only ──
    "fontconfig"              # depends: freetype, libexpat
    "xorgproto"
    "libxrender"              # depends: libx11
    "python"
    "glib"                    # depends: zlib, python, etc.
    "libjpeg-turbo"
    "libexif"
    "libimagequant"
    "littlecms"
    "jbig2dec"                # NEW - depends: libpng
    "libidn"                  # NEW - depends: libiconv
    "libgraphite"             # NEW - depends: libc++
    "libde265"                # NEW - depends: libc++
    "libx265"                 # NEW - depends: libc++
    "libjasper"               # NEW - depends: libjpeg-turbo

    # ── Tier 2: Depend on Tier 1 packages ──
    "libtiff"                 # depends: libjpeg-turbo, zlib
    "libtool"                 # NEW - produces libltdl subpackage
    "libzip"                  # NEW - depends: zlib, openssl
    "fribidi"                 # NEW - depends: glib
    "liblqr"                  # NEW - depends: glib
    "libgts"                  # NEW - depends: glib
    "djvulibre"               # NEW - depends: libjpeg-turbo, libtiff
    "gdk-pixbuf"              # NEW - depends: glib, libpng, libtiff, libjpeg-turbo
    "openjpeg"
    "libwebp"                 # depends: giflib, libjpeg-turbo, libpng, libtiff

    # ── Tier 3: Mid-level graphics libraries ──
    "libcairo"                # depends: fontconfig, glib, libandroid-shmem, libandroid-execinfo, liblzo, libpixman
    "harfbuzz"                # NEW - depends: glib, libcairo, libgraphite
    "openjph"                 # NEW - depends: libtiff (JPEG2000 HTJ2K, needed by openexr 3.4+)
    "openexr"                 # depends: imath, zlib, openjph
    "libjxl"                  # depends: giflib, glib, libjpeg-turbo
    "libheif"                 # depends: gdk-pixbuf, libaom, libdav1d, libde265, librav1e, libx265
    "libnss"                  # NEW - depends: libnspr

    # ── Tier 4: Text rendering and processing ──
    "ghostscript"             # NEW - depends: fontconfig, jbig2dec, libidn, libjpeg-turbo, littlecms, openjpeg
    "pango"                   # depends: fontconfig, fribidi, glib, harfbuzz, libcairo
    "libraqm"                 # NEW - depends: harfbuzz, fribidi
    "libraw"                  # NEW - depends: libjasper, libjpeg-turbo, littlecms

    # ── Tier 5: High-level rendering libraries ──
    "librsvg"                 # depends: gdk-pixbuf, glib, harfbuzz, libcairo, pango
    "libgd"                   # NEW - depends: fontconfig, libheif, libjpeg-turbo, libpng, libtiff, libwebp
    "graphviz"                # NEW - depends: gdk-pixbuf, harfbuzz, libcairo, libgd, libgts, libtool, librsvg, pango

    # ── Tier 6: GPG stack (needed by poppler) ──
    "gpgme"                   # NEW - depends: gnupg, libassuan, libgpg-error
    "gpgmepp"                 # NEW - depends: gpgme

    # ── Tier 7: Top-level processing suites ──
    "imagemagick"             # depends: djvulibre, fftw, ghostscript, graphviz, harfbuzz, imagemagick deps...
    "poppler"                 # depends: gpgme, gpgmepp, libcairo, libnspr, libnss
    "leptonica"               # NEW - depends: giflib, libjpeg-turbo, libpng, libtiff, libwebp, openjpeg
    "libarchive"              # depends: zlib

    # ── The main package ──
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

                # Collect subpackage .debs (e.g., libtool produces libltdl)
                if [ -d "$(dirname "$SCRIPT_DIR")/packages/${pkg}" ]; then
                    for subpkg in "$(dirname "$SCRIPT_DIR")"/packages/${pkg}/*.subpackage.sh; do
                        [ -f "$subpkg" ] || continue
                        subpkg_name=$(basename "$subpkg" .subpackage.sh)
                        while IFS= read -r -d '' deb_file; do
                            cp "$deb_file" "$OUTPUT_DIR/"
                            echo "     Copied subpackage: $(basename "$deb_file")"
                            deb_count=$((deb_count + 1))
                        done < <(find "$deb_dir" -name "${subpkg_name}_*.deb" -print0 2>/dev/null)
                    done
                fi
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

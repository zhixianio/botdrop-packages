#!/bin/bash
##
## Script for creating APT repository from built .deb packages.
##
## Usage (legacy):
##   ./scripts/create-botdrop-repo.sh [debs-dir] [repo-dir] [arch]
##
## Usage (extended):
##   ./scripts/create-botdrop-repo.sh [debs-dir] [repo-dir] [arch] [options]
##
## Options:
##   --no-archive                 Do not create botdrop-repo-ARCH.zip
##   --merge-existing <dir>       Merge packages from an existing repository dir
##                                (expects pool/main and dists/ layout) before
##                                adding newly built packages.
##
## Output:
##   - repo-dir/              APT repository structure
##   - botdrop-repo-ARCH.zip  Compressed repository archive (unless --no-archive)
##

set -euo pipefail

DEBS_DIR="${1:-./debs-output}"
REPO_DIR="${2:-./botdrop-repo}"
ARCH="${3:-aarch64}"
shift $(( $# >= 3 ? 3 : $# )) || true

CREATE_ARCHIVE=true
MERGE_EXISTING=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-archive)
            CREATE_ARCHIVE=false
            shift
            ;;
        --merge-existing)
            MERGE_EXISTING="${2:-}"
            if [[ -z "$MERGE_EXISTING" ]]; then
                echo "❌ Error: --merge-existing requires a directory argument"
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "❌ Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# Detect stat command (BSD vs GNU)
if stat -f%z /dev/null >/dev/null 2>&1; then
    # BSD stat (macOS)
    STAT_SIZE_CMD="stat -f%z"
else
    # GNU stat (Linux)
    STAT_SIZE_CMD="stat -c%s"
fi

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | awk '{print $1}'
    else
        md5 -q "$1"
    fi
}

##
## Parse .deb control file and generate Packages entry
##
## Args:
##   $1: Path to .deb file
##   $2: Filename (for Filename: field)
##
extract_control_from_deb() {
    local deb_file="$1"
    local tmpdir

    # Use bsdtar to extract .deb (works on macOS where ar has trailing-slash bugs)
    tmpdir=$(mktemp -d)
    if ! bsdtar -xf "$deb_file" -C "$tmpdir" 2>/dev/null; then
        rm -rf "$tmpdir"
        return 1
    fi

    local control_tar
    control_tar=$(ls "$tmpdir"/control.tar.* 2>/dev/null | head -1)
    if [[ -z "$control_tar" ]]; then
        rm -rf "$tmpdir"
        return 1
    fi

    local result
    case "$control_tar" in
        *.xz)  result=$(xz -d < "$control_tar" | tar -xO control 2>/dev/null || xz -d < "$control_tar" | tar -xO ./control 2>/dev/null) ;;
        *.gz)  result=$(gzip -d < "$control_tar" | tar -xO control 2>/dev/null || gzip -d < "$control_tar" | tar -xO ./control 2>/dev/null) ;;
        *.zst) result=$(zstd -d -q < "$control_tar" | tar -xO control 2>/dev/null || zstd -d -q < "$control_tar" | tar -xO ./control 2>/dev/null) ;;
        *.bz2) result=$(bzip2 -d < "$control_tar" | tar -xO control 2>/dev/null || bzip2 -d < "$control_tar" | tar -xO ./control 2>/dev/null) ;;
        *)     rm -rf "$tmpdir"; return 1 ;;
    esac

    rm -rf "$tmpdir"
    echo "$result"
}

parse_deb_control() {
    local deb_file="$1"
    local filename="$2"
    local file_size
    local sha256

    file_size=$($STAT_SIZE_CMD "$deb_file")
    sha256=$(sha256_of "$deb_file")

    # Extract control file from .deb
    # .deb format: ar archive containing control.tar.* and data.tar.*
    extract_control_from_deb "$deb_file" | \
    awk -v filename="$filename" -v size="$file_size" -v sha256="$sha256" '
        BEGIN {
            print "Filename: pool/main/" filename
            in_description = 0
        }

        # Copy these fields directly
        /^Package:/ { print; next }
        /^Version:/ { print; next }
        /^Architecture:/ { print; next }
        /^Maintainer:/ { print; next }
        /^Installed-Size:/ { print; next }
        /^Depends:/ { print; next }
        /^Recommends:/ { print; next }
        /^Suggests:/ { print; next }
        /^Conflicts:/ { print; next }
        /^Breaks:/ { print; next }
        /^Replaces:/ { print; next }
        /^Provides:/ { print; next }
        /^Section:/ { print; next }
        /^Priority:/ { print; next }
        /^Homepage:/ { print; next }

        # Handle Description (multi-line field)
        /^Description:/ {
            in_description = 1
            desc = $0
            next
        }

        in_description && /^ / {
            desc = desc "\n" $0
            next
        }

        in_description && !/^ / {
            print desc
            in_description = 0
            # Process this line normally
        }

        # Other fields ignored

        END {
            if (in_description) {
                print desc
            }
            print "Size: " size
            print "SHA256: " sha256
            print ""
        }
    '
}

generate_release() {
    local release_path="$1"
    local packages_rel="main/binary-${ARCH}/Packages"
    local packages_gz_rel="main/binary-${ARCH}/Packages.gz"
    local packages_file="$(dirname "$release_path")/${packages_rel}"
    local packages_gz_file="$(dirname "$release_path")/${packages_gz_rel}"

    local packages_md5 packages_sha256 packages_size
    local packages_gz_md5 packages_gz_sha256 packages_gz_size

    packages_md5=$(md5_of "$packages_file")
    packages_sha256=$(sha256_of "$packages_file")
    packages_size=$($STAT_SIZE_CMD "$packages_file")

    packages_gz_md5=$(md5_of "$packages_gz_file")
    packages_gz_sha256=$(sha256_of "$packages_gz_file")
    packages_gz_size=$($STAT_SIZE_CMD "$packages_gz_file")

    cat > "$release_path" << EOF
Origin: BotDrop
Label: BotDrop Packages
Suite: stable
Codename: stable
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
Architectures: ${ARCH}
Components: main
Description: BotDrop custom packages for sharp support
MD5Sum:
 ${packages_md5} ${packages_size} ${packages_rel}
 ${packages_gz_md5} ${packages_gz_size} ${packages_gz_rel}
SHA256:
 ${packages_sha256} ${packages_size} ${packages_rel}
 ${packages_gz_sha256} ${packages_gz_size} ${packages_gz_rel}
EOF
}

echo "========================================"
echo "  BotDrop APT Repository Creator"
echo "========================================"
echo ""
echo "Input directory:  $DEBS_DIR"
echo "Output directory: $REPO_DIR"
echo "Architecture:     $ARCH"
if [[ -n "$MERGE_EXISTING" ]]; then
    echo "Merge existing:   $MERGE_EXISTING"
fi
if [[ "$CREATE_ARCHIVE" == false ]]; then
    echo "Archive:          disabled (--no-archive)"
fi
echo ""

# Check input directory
if [ ! -d "$DEBS_DIR" ]; then
    echo "❌ Error: Input directory not found: $DEBS_DIR"
    exit 1
fi

deb_count=$(find "$DEBS_DIR" -maxdepth 1 -name '*.deb' -type f | wc -l | tr -d ' ')
if [ "$deb_count" -eq 0 ]; then
    echo "❌ Error: No .deb files found in $DEBS_DIR"
    exit 1
fi

echo "Found $deb_count new .deb files"
echo ""

# Clean and create repository structure
echo "Creating repository structure..."
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR/pool/main"
mkdir -p "$REPO_DIR/dists/stable/main/binary-${ARCH}"

# Merge existing repo first (incremental update)
if [[ -n "$MERGE_EXISTING" ]]; then
    if [[ -d "$MERGE_EXISTING/pool/main" ]]; then
        echo "Merging existing packages from $MERGE_EXISTING/pool/main ..."
        existing_debs=("$MERGE_EXISTING"/pool/main/*.deb)
        if [[ -e "${existing_debs[0]}" ]]; then
            cp -f "${existing_debs[@]}" "$REPO_DIR/pool/main/"
        else
            echo "  (no existing .deb files to merge)"
        fi
    else
        echo "⚠️  Warning: merge source missing pool/main: $MERGE_EXISTING"
    fi
fi

# Copy newly built .deb files to pool (overwrite existing versions)
echo "Copying new .deb files to pool..."
cp -f "$DEBS_DIR"/*.deb "$REPO_DIR/pool/main/" 2>/dev/null || {
    echo "❌ Error: Failed to copy .deb files"
    exit 1
}

# Generate Packages file
echo "Generating Packages index..."
packages_file="$REPO_DIR/dists/stable/main/binary-${ARCH}/Packages"
> "$packages_file"

pkg_count=0
for deb in "$REPO_DIR/pool/main"/*.deb; do
    [ -f "$deb" ] || continue

    filename=$(basename "$deb")
    printf "  Processing: %-50s" "$filename"

    if parse_deb_control "$deb" "$filename" >> "$packages_file"; then
        echo "✓"
        pkg_count=$((pkg_count + 1))
    else
        echo "✗"
        echo "⚠️  Warning: Failed to parse $filename"
    fi
done

echo ""
echo "Processed $pkg_count total packages"

# Compress Packages file
echo "Compressing Packages index..."
gzip -kf "$packages_file"

# Generate component Release (kept for compatibility)
echo "Generating Release files..."
cat > "$REPO_DIR/dists/stable/main/binary-${ARCH}/Release" << EOF
Archive: stable
Component: main
Origin: BotDrop
Label: BotDrop Packages
Architecture: ${ARCH}
EOF

# Generate distribution Release with required checksums
generate_release "$REPO_DIR/dists/stable/Release"

archive_name="botdrop-repo-${ARCH}.zip"
archive_path="$(dirname "$REPO_DIR")/${archive_name}"

if [[ "$CREATE_ARCHIVE" == true ]]; then
    echo "Creating repository archive..."
    (cd "$(dirname "$REPO_DIR")" && zip -r -q "$archive_name" "$(basename "$REPO_DIR")")
fi

echo ""
echo "========================================"
echo "  Repository Created Successfully"
echo "========================================"
echo ""
echo "📦 Packages:          $pkg_count"
echo "📂 Repository:        $REPO_DIR"
if [[ "$CREATE_ARCHIVE" == true ]]; then
    echo "🗜️  Archive:           $archive_path"
    echo "💾 Archive size:      $(du -h "$archive_path" | cut -f1)"
fi
echo ""
echo "Repository structure:"
echo "  $REPO_DIR/"
echo "  ├── pool/main/              ($pkg_count .deb files)"
echo "  └── dists/stable/main/"
echo "      └── binary-${ARCH}/"
echo "          ├── Packages        ($(wc -l < "$packages_file") lines)"
echo "          ├── Packages.gz"
echo "          └── Release"
echo ""
if [[ "$CREATE_ARCHIVE" == true ]]; then
    echo "Next step: Upload to GitHub Release with:"
    echo "  gh release create packages-YYYY.MM.DD-r1 $archive_path"
    echo ""
fi
echo "========================================"
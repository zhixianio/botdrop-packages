#!/bin/bash
##
## Script for creating APT repository from built .deb packages.
##
## This creates a standard Debian repository structure without requiring
## dpkg-scanpackages or other Debian tools, making it portable across
## different build environments (macOS, Linux, Docker).
##
## Usage:
##   ./scripts/create-botdrop-repo.sh [debs-dir] [repo-dir] [arch]
##
## Arguments:
##   debs-dir   Directory containing .deb files (default: ./debs-output)
##   repo-dir   Output directory for repository (default: ./botdrop-repo)
##   arch       Architecture (default: aarch64)
##
## Output:
##   - repo-dir/              APT repository structure
##   - botdrop-repo-ARCH.zip  Compressed repository archive
##

set -e

DEBS_DIR="${1:-./debs-output}"
REPO_DIR="${2:-./botdrop-repo}"
ARCH="${3:-aarch64}"

# Detect stat command (BSD vs GNU)
if stat -f%z /dev/null >/dev/null 2>&1; then
    # BSD stat (macOS)
    STAT_SIZE_CMD="stat -f%z"
else
    # GNU stat (Linux)
    STAT_SIZE_CMD="stat -c%s"
fi

##
## Parse .deb control file and generate Packages entry
##
## Args:
##   $1: Path to .deb file
##   $2: Filename (for Filename: field)
##
parse_deb_control() {
    local deb_file="$1"
    local filename="$2"
    local file_size

    file_size=$($STAT_SIZE_CMD "$deb_file")

    # Extract control file from .deb
    # .deb format: ar archive containing control.tar.xz and data.tar.xz
    ar -p "$deb_file" control.tar.xz 2>/dev/null | xz -d | tar -xO ./control 2>/dev/null | \
    awk -v filename="$filename" -v size="$file_size" '
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
            print ""
        }
    '
}

echo "========================================"
echo "  BotDrop APT Repository Creator"
echo "========================================"
echo ""
echo "Input directory:  $DEBS_DIR"
echo "Output directory: $REPO_DIR"
echo "Architecture:     $ARCH"
echo ""

# Check input directory
if [ ! -d "$DEBS_DIR" ]; then
    echo "❌ Error: Input directory not found: $DEBS_DIR"
    exit 1
fi

deb_count=$(ls -1 "$DEBS_DIR"/*.deb 2>/dev/null | wc -l | tr -d ' ')
if [ "$deb_count" -eq 0 ]; then
    echo "❌ Error: No .deb files found in $DEBS_DIR"
    exit 1
fi

echo "Found $deb_count .deb files"
echo ""

# Clean and create repository structure
echo "Creating repository structure..."
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR/pool/main"
mkdir -p "$REPO_DIR/dists/stable/main/binary-${ARCH}"

# Copy .deb files to pool
echo "Copying .deb files to pool..."
cp "$DEBS_DIR"/*.deb "$REPO_DIR/pool/main/" 2>/dev/null || {
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
echo "Processed $pkg_count packages"

# Compress Packages file
echo "Compressing Packages index..."
gzip -k "$packages_file"

# Generate Release files
echo "Generating Release files..."

cat > "$REPO_DIR/dists/stable/main/binary-${ARCH}/Release" << EOF
Archive: stable
Component: main
Origin: BotDrop
Label: BotDrop Packages
Architecture: ${ARCH}
EOF

cat > "$REPO_DIR/dists/stable/Release" << EOF
Origin: BotDrop
Label: BotDrop Packages
Suite: stable
Codename: stable
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
Architectures: ${ARCH}
Components: main
Description: BotDrop custom packages for sharp support
EOF

# Create archive
echo "Creating repository archive..."
archive_name="botdrop-repo-${ARCH}.zip"

cd "$(dirname "$REPO_DIR")"
zip -r -q "$archive_name" "$(basename "$REPO_DIR")"
cd - > /dev/null

echo ""
echo "========================================"
echo "  Repository Created Successfully"
echo "========================================"
echo ""
echo "📦 Packages:          $pkg_count"
echo "📂 Repository:        $REPO_DIR"
echo "🗜️  Archive:           $archive_name"
echo "💾 Archive size:      $(du -h "$archive_name" | cut -f1)"
echo ""
echo "Repository structure:"
echo "  $REPO_DIR/"
echo "  ├── pool/main/              ($deb_count .deb files)"
echo "  └── dists/stable/main/"
echo "      └── binary-${ARCH}/"
echo "          ├── Packages        ($(wc -l < "$packages_file") lines)"
echo "          ├── Packages.gz"
echo "          └── Release"
echo ""
echo "Next step: Upload to GitHub Release with:"
echo "  gh release create packages-YYYY.MM.DD-r1 $archive_name"
echo ""
echo "========================================"

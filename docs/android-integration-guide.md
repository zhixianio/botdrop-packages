# BotDrop Android Integration Guide - Sharp Support

## Quick Start

The package repository is live and ready for integration:

**Repository URL:**
```
https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/
```

**Release Information:**
- **Packages:** 33 .deb files (libvips + dependencies + build tools)
- **Size:** 32 MB (compressed)
- **Architecture:** aarch64
- **Latest Release:** packages-2026.02.14-r1

---

## Required Changes in botdrop-android

### 1. Add Constant (TermuxConstants.java)

**File:** `termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java`

**Location:** Add after line ~515 (after TERMUX_PACKAGES_GITHUB_ISSUES_REPO_URL)

```java
/**
 * BotDrop custom packages repository URL
 * Provides libvips and dependencies for sharp image processing
 */
public static final String BOTDROP_PACKAGES_REPO_URL =
    "https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/";
```

### 2. Add Setup Method (TermuxBootstrap.java)

**File:** `termux-shared/src/main/java/com/termux/shared/termux/TermuxBootstrap.java`

**Location:** Add as a new method in the class

```java
/**
 * Setup BotDrop custom package repository for sharp support.
 * Creates sources.list.d/botdrop-packages.list
 *
 * Call this after bootstrap extraction, before first apt update.
 *
 * @param context The context for file operations
 */
public static void setupBotdropPackageRepository(@NonNull final Context context) {
    String logTag = "BotdropRepo";

    try {
        // Create sources.list.d directory
        File sourcesListD = new File(TermuxConstants.TERMUX_PREFIX_DIR_PATH + "/etc/apt/sources.list.d");
        if (!sourcesListD.exists()) {
            if (!sourcesListD.mkdirs()) {
                Logger.logError(logTag, "Failed to create sources.list.d directory");
                return;
            }
        }

        // Create botdrop-packages.list
        File botdropList = new File(sourcesListD, "botdrop-packages.list");

        // Only create if doesn't exist (don't overwrite user modifications)
        if (!botdropList.exists()) {
            String repoConfig =
                "# BotDrop custom packages repository\\n" +
                "# Provides libvips and dependencies for sharp image processing\\n" +
                "deb " + TermuxConstants.BOTDROP_PACKAGES_REPO_URL + " stable main\\n";

            FileUtils.writeStringToFile(botdropList, repoConfig, StandardCharsets.UTF_8);
            Logger.logInfo(logTag, "BotDrop package repository configured at: " + botdropList.getPath());
        } else {
            Logger.logDebug(logTag, "BotDrop repository config already exists, skipping");
        }

    } catch (Exception e) {
        Logger.logStackTraceWithMessage(logTag, "Failed to setup BotDrop repository", e);
    }
}
```

### 3. Call Setup Method (TermuxInstaller.java or similar)

**File:** Look for the file that handles bootstrap installation/extraction

**Location:** Find where bootstrap is extracted (search for "bootstrap" + "extract" or "setupBootstrap")

**Add after bootstrap extraction completes:**

```java
// Setup custom package repository for sharp support
TermuxBootstrap.setupBotdropPackageRepository(context);
```

**Example integration point:**
```java
private static void setupBootstrap(...) {
    // ... existing bootstrap extraction code ...

    // Extract bootstrap archive
    extractBootstrapArchive(context, bootstrapZipPath);

    // Setup BotDrop custom package repository
    TermuxBootstrap.setupBotdropPackageRepository(context);

    // ... continue with other initialization ...
}
```

---

## Testing

### 1. Build and Install Modified APK

After making the code changes:

```bash
# In botdrop-android directory
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/botdrop-app_*.apk
```

### 2. Verify Repository Configuration

Launch BotDrop app (first time installation), then:

```bash
adb shell
# Inside device shell

# Check repository is configured
cat $PREFIX/etc/apt/sources.list.d/botdrop-packages.list

# Expected output:
# # BotDrop custom packages repository
# # Provides libvips and dependencies for sharp image processing
# deb https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/ stable main
```

### 3. Test Package Installation

```bash
# Update package list (should succeed without errors)
pkg update

# Install libvips
pkg install libvips

# Verify installation
pkg list-installed | grep libvips
# Should show: libvips/stable 8.18.0-1 aarch64 [installed]
```

### 4. Test Sharp Installation

```bash
# Install Node.js sharp library
npm install sharp

# Test sharp functionality
node -e "const sharp = require('sharp'); sharp('test.jpg').metadata().then(m => console.log('Success:', m.width, 'x', m.height)).catch(e => console.error('Error:', e.message))"
```

**Expected:** Sharp should load successfully and process images

---

## Troubleshooting

### Issue: sources.list.d file not created

**Symptoms:** File doesn't exist after app launch

**Diagnosis:**
```bash
# Check logs
adb logcat | grep -i "BotdropRepo"
```

**Common causes:**
- Setup method not called
- Called before bootstrap extraction
- Directory permissions issue

**Fix:**
- Verify method is called after bootstrap extraction
- Check logcat for error messages
- Ensure TERMUX_PREFIX_DIR_PATH is correct

### Issue: pkg update fails

**Symptoms:**
```
E: The repository 'https://... stable Release' does not have a Release file.
```

**Diagnosis:**
```bash
# Check repository URL syntax
cat $PREFIX/etc/apt/sources.list.d/botdrop-packages.list

# Test URL accessibility
curl -I https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/dists/stable/Release
```

**Common causes:**
- Incorrect URL format (missing trailing slash, wrong path)
- Network connectivity issue
- Repository not yet published

**Fix:**
- Verify URL exactly matches: `https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/`
- Test network connection
- Verify release exists: https://github.com/zhixianio/botdrop-packages/releases/tag/packages-latest

### Issue: libvips not found

**Symptoms:**
```
E: Unable to locate package libvips
```

**Diagnosis:**
```bash
# Check if repository is in sources
cat $PREFIX/etc/apt/sources.list.d/botdrop-packages.list

# Update package lists
pkg update

# Search for libvips
pkg search libvips
```

**Common causes:**
- Repository not configured
- Package lists not updated
- Wrong architecture

**Fix:**
- Run `pkg update` first
- Check repository configuration exists
- Verify device is aarch64: `uname -m`

### Issue: Sharp installation fails

**Symptoms:**
```
Error: Cannot find module '../build/Release/sharp-linux-arm64v8.node'
```

**Diagnosis:**
```bash
# Check if libvips is installed
pkg list-installed | grep libvips

# Check build tools
pkg list-installed | grep -E "(python|make|pkg-config)"
```

**Common causes:**
- libvips not installed
- Missing build dependencies
- Node.js version incompatibility

**Fix:**
```bash
# Install all required packages
pkg install libvips pkg-config python make

# Rebuild sharp
npm rebuild sharp --build-from-source
```

---

## Package List

The repository contains 33 packages (~170 MB installed, 32 MB compressed):

### Core Package
- `libvips` (8.18.0-1) - High-performance image processing library

### Build Tools (required when npm builds sharp)
- `pkg-config` - Package configuration helper
- `ndk-sysroot` - Android NDK system headers
- `python` - Python runtime (for build scripts)
- `make` - Build automation
- `binutils-is-llvm` - Binary utilities
- `which` - Command lookup utility

### Image Format Libraries
- `libjpeg-turbo` - JPEG support
- `libpng` - PNG support
- `libwebp` - WebP support
- `libtiff` - TIFF support
- `libheif` - HEIF/HEIC support
- `libjxl` - JPEG XL support
- `cgif` - GIF support

### Graphics Libraries
- `libcairo` - 2D graphics
- `pango` - Text rendering
- `librsvg` - SVG support
- `poppler` - PDF rendering
- `imagemagick` - Image manipulation toolkit

### Core Dependencies
- `glib` - Core library
- `fontconfig` - Font configuration
- `fftw` - Fast Fourier transform
- `imath` - Math library
- `openexr` - OpenEXR format
- `openjpeg` - JPEG 2000
- `littlecms` - Color management
- `libexif` - EXIF metadata
- `libimagequant` - Image quantization
- `libexpat` - XML parser
- `libarchive` - Archive formats
- `xorgproto` - X11 protocol headers
- `libxrender` - X11 rendering
- `zlib` - Compression library

---

## Architecture Notes

### Why Custom Repository?

BotDrop uses custom package name `app.botdrop` instead of `com.termux`, which changes all file paths from `/data/data/com.termux` to `/data/data/app.botdrop`.

Official Termux packages are compiled with hardcoded `com.termux` paths, so they're incompatible. All packages must be rebuilt with the `app.botdrop` prefix.

### Repository Updates

The repository is automatically maintained:
- **URL:** `packages-latest` tag always points to most recent build
- **Frequency:** Updated when package definitions change
- **CI/CD:** GitHub Actions builds and publishes automatically

To update to newer package versions, the botdrop-packages repository maintainer triggers a rebuild.

---

## Additional Resources

- **Design Document:** `docs/plans/2026-02-14-sharp-support-design.md` (in botdrop-packages repo)
- **Implementation Plan:** `docs/plans/2026-02-14-sharp-support-implementation.md`
- **GitHub Releases:** https://github.com/zhixianio/botdrop-packages/releases
- **Sharp Documentation:** https://sharp.pixelplumbing.com/

---

## Support

For issues with:
- **Package repository / builds:** Open issue in `botdrop-packages` repo
- **Android integration:** Open issue in `botdrop-android` repo
- **Sharp library itself:** Refer to https://github.com/lovell/sharp

---

**Document Version:** 1.0
**Last Updated:** 2026-02-14
**Repository Version:** packages-2026.02.14-r1

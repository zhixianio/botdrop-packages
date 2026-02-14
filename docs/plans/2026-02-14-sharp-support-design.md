# BotDrop Sharp 库支持设计方案

**日期：** 2026-02-14
**状态：** 设计完成，待实施
**维护者：** botdrop-packages (后端), botdrop-android (前端集成)

---

## 背景

BotDrop 需要支持 Node.js 的 `sharp` 图像处理库。Sharp 依赖 `libvips` 及其 33 个依赖包（约 170 MB 安装大小）。

由于 BotDrop 使用自定义包名 `app.botdrop`（而非 `com.termux`），无法使用官方 Termux 仓库，需要自建包仓库。

---

## 整体架构

```
┌─────────────────────────────────────────────────┐
│  1. 包构建系统 (botdrop-packages)              │
│     - 构建 33 个 sharp 依赖包                   │
│     - 生成 APT 仓库索引                         │
│     - 发布到 GitHub Releases                    │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  2. 包仓库托管 (GitHub Releases)                │
│     - URL: github.com/.../releases/.../         │
│     - 包含: botdrop-repo-aarch64.zip            │
│     - 结构: APT 仓库格式                        │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  3. App 集成 (botdrop-android)                  │
│     - 首次启动时配置 APT 源                     │
│     - 创建 sources.list.d/botdrop-packages.list │
│     - 用户可使用: pkg install libvips           │
└─────────────────────────────────────────────────┘
```

---

## 第一部分：包构建 (botdrop-packages)

### 1.1 包列表

需要构建的 33 个包（按依赖顺序）：

**构建工具（用于编译 sharp）：**
- pkg-config
- ndk-sysroot
- python
- make
- binutils-is-llvm
- which

**libvips 及其依赖：**
- zlib, libexpat, libc++
- cgif, fftw, fontconfig, glib
- imath, libjpeg-turbo, libpng, libexif
- libimagequant, littlecms, libwebp, libtiff
- libheif, libjxl, openexr, openjpeg
- xorgproto, libxrender, libcairo, pango
- librsvg, poppler, imagemagick, libarchive
- libvips

**总计：** 约 170 MB（已安装）/ 50-70 MB（压缩后）

### 1.2 批量构建脚本

**文件：** `scripts/build-sharp-packages.sh`

```bash
#!/bin/bash
set -e

SHARP_PACKAGES=(
    # 构建工具
    "pkg-config" "ndk-sysroot" "python" "make"
    "binutils-is-llvm" "which"

    # libvips 依赖（按依赖顺序）
    "zlib" "libexpat" "libc++"
    "cgif" "fftw" "fontconfig" "glib"
    "imath" "libjpeg-turbo" "libpng" "libexif"
    "libimagequant" "littlecms" "libwebp" "libtiff"
    "libheif" "libjxl" "openexr" "openjpeg"
    "xorgproto" "libxrender" "libcairo" "pango"
    "librsvg" "poppler" "imagemagick" "libarchive"
    "libvips"
)

ARCH="${1:-aarch64}"
OUTPUT_DIR="${2:-./debs-output}"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "  构建 Sharp 依赖包"
echo "  架构: $ARCH | 输出: $OUTPUT_DIR"
echo "========================================"

for pkg in "${SHARP_PACKAGES[@]}"; do
    echo "[$(date '+%H:%M:%S')] 构建 $pkg ..."

    if ./build-package.sh -a "$ARCH" "$pkg"; then
        echo "  ✅ 成功"
        find output -name "${pkg}_*.deb" -exec cp {} "$OUTPUT_DIR/" \;
    else
        echo "  ⚠️  跳过（可能已存在）"
    fi
done

echo "✅ 构建完成: $(ls -1 "$OUTPUT_DIR"/*.deb | wc -l) 个包"
```

### 1.3 仓库创建脚本

**文件：** `scripts/create-botdrop-repo.sh`

```bash
#!/bin/bash
set -e

DEBS_DIR="${1:-./debs-output}"
REPO_DIR="${2:-./botdrop-repo}"
ARCH="${3:-aarch64}"

# 解析 .deb 控制信息（无需 dpkg-scanpackages）
parse_deb_control() {
    local deb_file="$1"
    local filename="$2"

    ar -p "$deb_file" control.tar.xz 2>/dev/null | tar -xJO ./control 2>/dev/null | \
    awk -v filename="$filename" -v size="$(stat -f%z "$deb_file" 2>/dev/null || stat -c%s "$deb_file" 2>/dev/null)" '
        BEGIN { print "Filename: pool/main/" filename }
        /^Package:/ { print }
        /^Version:/ { print }
        /^Architecture:/ { print }
        /^Maintainer:/ { print }
        /^Installed-Size:/ { print }
        /^Depends:/ { print }
        /^Description:/ {
            desc=$0
            while (getline > 0 && /^ /) desc = desc "\n" $0
            print desc
            if (!/^ /) print $0
        }
        END { print "Size: " size }
    '
    echo ""
}

echo "创建 BotDrop APT 仓库..."

# 创建目录结构
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR/pool/main"
mkdir -p "$REPO_DIR/dists/stable/main/binary-${ARCH}"

# 复制 .deb 文件
cp "$DEBS_DIR"/*.deb "$REPO_DIR/pool/main/"

# 生成 Packages 索引
packages_file="$REPO_DIR/dists/stable/main/binary-${ARCH}/Packages"
> "$packages_file"

for deb in "$REPO_DIR/pool/main"/*.deb; do
    [ -f "$deb" ] || continue
    filename=$(basename "$deb")
    echo "  处理: $filename"
    parse_deb_control "$deb" "$filename" >> "$packages_file"
done

gzip -k "$packages_file"

# 生成 Release 文件
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

# 打包仓库
cd "$(dirname "$REPO_DIR")"
zip -r "botdrop-repo-${ARCH}.zip" "$(basename "$REPO_DIR")" > /dev/null

echo "✅ 仓库创建完成: botdrop-repo-${ARCH}.zip"
```

### 1.4 GitHub Actions 自动化

**文件：** `.github/workflows/build-sharp-packages.yml`

```yaml
name: Build Sharp Packages

on:
  workflow_dispatch:
  push:
    branches:
      - master
    paths:
      - 'scripts/build-sharp-packages.sh'
      - 'scripts/create-botdrop-repo.sh'

permissions:
  contents: write

jobs:
  build-packages:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build sharp packages in Docker
        run: |
          ./scripts/run-docker.sh ./scripts/build-sharp-packages.sh aarch64 ./debs-output

      - name: Create APT repository
        run: |
          chmod +x ./scripts/create-botdrop-repo.sh
          ./scripts/create-botdrop-repo.sh ./debs-output ./botdrop-repo aarch64

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: botdrop-repo-aarch64
          path: botdrop-repo-aarch64.zip

  publish:
    needs: build-packages
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/master'

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: botdrop-repo-aarch64
          path: ./

      - name: Create release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          TAG="packages-$(date '+%Y.%m.%d')-r1"
          gh release create "$TAG" \
            --title "BotDrop Package Repository $TAG" \
            --notes "Sharp dependencies for app.botdrop

            ## Included packages
            - libvips and all 32 dependencies
            - Build tools (python, make, pkg-config)

            ## Usage
            This repository is automatically configured in BotDrop app.
            Users can install packages with: \`pkg install libvips\`" \
            botdrop-repo-aarch64.zip
```

---

## 第二部分：App 集成 (botdrop-android)

### 2.1 自动配置 APT 源

**需要修改的文件：** `termux-shared/src/main/java/com/termux/shared/termux/TermuxBootstrap.java`
或相关的 bootstrap 初始化代码。

**仓库 URL（已发布）：**
```
https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/
```

**添加常量（TermuxConstants.java）：**

```java
/**
 * BotDrop custom packages repository URL
 * Provides libvips and dependencies for sharp image processing
 */
public static final String BOTDROP_PACKAGES_REPO_URL =
    "https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/";
```

**添加初始化方法：**

```java
/**
 * Setup BotDrop custom package repository for sharp support.
 * Creates /data/data/app.botdrop/files/usr/etc/apt/sources.list.d/botdrop-packages.list
 *
 * This should be called after bootstrap extraction and before first apt update.
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
                "# BotDrop custom packages repository\n" +
                "# Provides libvips and dependencies for sharp image processing\n" +
                "deb " + TermuxConstants.BOTDROP_PACKAGES_REPO_URL + " stable main\n";

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

### 2.2 调用时机

在 Bootstrap 解压完成后调用。找到类似这样的代码位置：

```java
// 在 TermuxInstaller.java 或类似文件中
private static void setupBootstrap(...) {
    // ... 现有的 bootstrap 解压逻辑 ...

    // 解压完成后，配置 BotDrop 仓库
    TermuxBootstrap.setupBotdropPackageRepository(context);

    // ... 继续其他初始化 ...
}
```

**关键点：**
- ✅ 必须在 bootstrap 解压**之后**调用（确保目录存在）
- ✅ 必须在用户首次运行 `pkg update` **之前**调用
- ✅ 只创建一次，不覆盖用户修改

### 2.3 测试验证

用户安装 BotDrop 后应该能够：

```bash
# 1. 检查仓库是否配置
cat $PREFIX/etc/apt/sources.list.d/botdrop-packages.list

# 输出应该包含:
# deb https://github.com/zhixianio/botdrop-packages/releases/download/packages-latest/ stable main

# 2. 更新包索引
pkg update

# 3. 安装 libvips
pkg install libvips

# 4. 测试 sharp
npm install sharp
node -e "require('sharp')('test.jpg').metadata().then(m=>console.log(m)).catch(console.error)"
```

---

## 第三部分：用户体验流程

### 3.1 首次安装

1. 用户安装 BotDrop APK
2. App 首次启动，解压 bootstrap
3. **App 自动创建** `/data/data/app.botdrop/files/usr/etc/apt/sources.list.d/botdrop-packages.list`
4. 用户打开终端，运行 `pkg update`
5. 用户可以正常使用 `pkg install libvips`

### 3.2 安装 Sharp

```bash
# 用户工作流程
$ pkg update
$ pkg install libvips pkg-config python make  # 安装依赖
$ npm install sharp                             # 安装 sharp
$ node test-sharp.js                            # 测试
```

---

## 实施计划

### botdrop-packages 仓库（你负责）

- [ ] 创建 `scripts/build-sharp-packages.sh`
- [ ] 创建 `scripts/create-botdrop-repo.sh`
- [ ] 创建 `.github/workflows/build-sharp-packages.yml`
- [ ] 测试构建流程（手动触发 workflow）
- [ ] 验证 GitHub Release 创建成功

### botdrop-android 仓库（Android 维护者负责）

- [ ] 在 `TermuxConstants.java` 添加 `BOTDROP_PACKAGES_REPO_URL` 常量
- [ ] 实现 `setupBotdropPackageRepository()` 方法
- [ ] 在 bootstrap 初始化流程中调用该方法
- [ ] 测试：全新安装后验证 sources.list.d 文件创建
- [ ] 测试：运行 `pkg update && pkg install libvips`

---

## 技术细节

### 为什么需要自建仓库？

BotDrop 修改了包名为 `app.botdrop`（在 `scripts/properties.sh` 中定义）：
```bash
TERMUX_APP__PACKAGE_NAME="app.botdrop"
```

这导致所有路径从 `/data/data/com.termux` 变为 `/data/data/app.botdrop`。
官方 Termux 包是为 `com.termux` 编译的，包含硬编码路径，因此**必须重新编译所有包**。

### 为什么不全部放入 bootstrap？

**方案对比：**

| 方案 | 优点 | 缺点 |
|------|------|------|
| **全部放 bootstrap** | 用户开箱即用 | Bootstrap +50-70MB，所有用户都下载 |
| **包仓库（当前方案）** | Bootstrap 保持轻量，按需安装 | 需要维护仓库，初次设置复杂 |

选择包仓库方案是因为：
- ✅ 长期灵活性更好（可持续添加新包）
- ✅ 不强制所有用户下载大包
- ✅ 可以独立更新包版本

---

## 常见问题

**Q: 如果用户修改了 botdrop-packages.list 怎么办？**
A: App 只在文件不存在时创建，不会覆盖用户修改。

**Q: 如何更新仓库中的包？**
A: 修改 botdrop-packages 仓库后，GitHub Actions 自动构建并发布新 release。用户运行 `pkg update && pkg upgrade` 即可更新。

**Q: 如何支持多架构（arm, x86_64）？**
A: 修改 GitHub Actions 的 matrix 策略，并为每个架构构建独立的仓库。

**Q: 仓库 URL 如何动态更新？**
A: 使用 `packages-latest` 作为 tag，每次发布时更新该 tag 指向最新 release。或使用固定版本号，通过 App 更新推送新的仓库 URL。

---

## 附录：目录结构

### botdrop-packages 新增文件
```
botdrop-packages/
├── scripts/
│   ├── build-sharp-packages.sh       # 批量构建脚本
│   └── create-botdrop-repo.sh        # 仓库生成脚本
├── .github/workflows/
│   └── build-sharp-packages.yml      # CI/CD 自动化
└── docs/plans/
    └── 2026-02-14-sharp-support-design.md  # 本文档
```

### GitHub Release 产物

**Release URL:** https://github.com/zhixianio/botdrop-packages/releases/tag/packages-latest

**Latest Release:** packages-2026.02.14-r1 (33 packages, 32 MB)

```
Release: packages-2026.02.14-r1 / packages-latest
└── botdrop-repo-aarch64.zip
    └── botdrop-repo/
        ├── pool/main/
        │   ├── libvips_8.18.0-1_aarch64.deb
        │   ├── pkg-config_*.deb
        │   └── ... (33 个 .deb 文件)
        └── dists/stable/main/binary-aarch64/
            ├── Packages
            ├── Packages.gz
            └── Release
```

### BotDrop 设备上的文件
```
/data/data/app.botdrop/files/usr/
└── etc/apt/
    ├── sources.list              # Termux 官方镜像（如果有）
    └── sources.list.d/
        └── botdrop-packages.list # BotDrop 自定义仓库（App 创建）
```

---

**文档版本：** 1.0
**最后更新：** 2026-02-14

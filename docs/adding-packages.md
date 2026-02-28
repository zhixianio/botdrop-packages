# Adding Packages to BotDrop APT Repository

This guide explains how to add new packages to the BotDrop APT repository hosted on GitHub Pages.

## Background (why BotDrop is special)

BotDrop uses app package name `app.botdrop` instead of `com.termux`.

That means packages with hardcoded paths must be built with:

- `TERMUX_APP__PACKAGE_NAME=app.botdrop`

In this repository, that value is already set in `scripts/properties.sh` for BotDrop build flows.

---

## 1) Build a single package locally

Run in repo root:

```bash
./scripts/run-docker.sh ./scripts/build-package.sh <package-name> aarch64
```

Example:

```bash
./scripts/run-docker.sh ./scripts/build-package.sh libvips aarch64
```

Artifacts will be in output directories under repo root or build cache paths used by build scripts.

---

## 2) Add package to sharp build list (if part of sharp/native chain)

If the package is needed by sharp flow, edit:

- `scripts/build-sharp-packages.sh`

Add the package in the build order where dependencies are satisfied first.

Typical order rule:

1. low-level libs
2. codec/image deps
3. `libvips`
4. Node/native consumer packages

---

## 3) Build/refresh APT repo locally

After collecting `.deb` files into `./debs-output`:

```bash
./scripts/create-botdrop-repo.sh ./debs-output ./botdrop-repo aarch64
```

If you also built `sharp-node-addon_*.deb` on device, add it before generating the repo:

```bash
./scripts/import-sharp-addon.sh /path/to/sharp-node-addon_0.34.5_aarch64.deb ./debs-output
```

For CI-like incremental merge into existing repo:

```bash
./scripts/create-botdrop-repo.sh \
  ./debs-output ./botdrop-repo aarch64 \
  --merge-existing ./existing-pages-root \
  --no-archive
```

Expected structure:

- `dists/stable/main/binary-aarch64/Packages`
- `dists/stable/main/binary-aarch64/Packages.gz`
- `dists/stable/Release`
- `pool/main/*.deb`

---

## 4) Local APT repo test

Serve `botdrop-repo` over HTTP (example):

```bash
cd botdrop-repo
python3 -m http.server 8080
```

On test device (BotDrop/Termux-like env):

```bash
echo 'deb [trusted=yes] http://<host>:8080 stable main' > $PREFIX/etc/apt/sources.list.d/botdrop-test.list
pkg update
pkg install <your-package>
```

Verify package paths are under:

- `/data/data/app.botdrop/files/usr/...`

---

## 5) Trigger CI publish

CI workflow:

- `.github/workflows/deploy-apt-repo.yml`

Triggers:

- push to `master` when key scripts/workflow change
- manual `workflow_dispatch`

Pipeline does:

1. build sharp-related packages
2. merge with existing `gh-pages` repo content
3. regenerate APT indexes
4. deploy to GitHub Pages
5. publish `botdrop-repo-aarch64.zip` backup release

The CI workflow can also import the addon when manually dispatched:

```yaml
with:
  sharp_addon_deb: https://example.com/sharp-node-addon_0.34.5_aarch64.deb
```

Published APT root:

- `https://zhixianio.github.io/botdrop-packages/`

---

## ffmpeg example (next candidate)

When adding `ffmpeg`, usually include dependency chain first, then ffmpeg itself.

Suggested starter set (adjust by current package graph):

- `libx264`
- `libx265`
- `libvpx`
- `libopus`
- `libvorbis`
- `libass`
- `ffmpeg`

Recommended process:

1. Build each dependency package in order.
2. Put resulting `.deb` files into `debs-output/`.
3. Regenerate repo with `create-botdrop-repo.sh`.
4. Test install on BotDrop device via `pkg install ffmpeg`.

---

## Quick checklist

- [ ] Package builds successfully for `aarch64`
- [ ] No hardcoded `com.termux` paths in runtime-critical files
- [ ] APT indexes regenerated (`Packages`, `Packages.gz`, `Release`)
- [ ] Local install test passed
- [ ] CI publish completed

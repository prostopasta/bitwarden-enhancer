# Bitwarden Enhancer: Linux YubiKey Biometrics & Custom URL Column

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platforms: Linux / Web / Docker](https://img.shields.io/badge/Platforms-Desktop%20%7C%20Web%20%7C%20Vaultwarden-success.svg)]()

Custom enhancements and patches for the official **Bitwarden Desktop Client** (Linux) and **Web Vault** (Vaultwarden / self-hosted Web UI).

---

## 🚀 Key Features

1. **Persistent YubiKey & FIDO2 Unlock on Linux (Desktop)**
   - Fixes the upstream Bitwarden Linux limitation where biometric/security key sessions reset after application restart.
   - Leverages Linux Secret Service (FreeDesktop Secret Service API / GNOME Keyring / KWallet / KeePassXC) to persist master key unlock securely across restarts.
   - Upstream PR submitted to official clients: [bitwarden/clients#23033](https://github.com/bitwarden/clients/pull/23033).

2. **Primary URL Column (Replaces "Owner" Column)**
   - Replaces the rarely needed "Owner" / "Владелец" column with the item's primary **URL** directly in vault table view.
   - Instant visual identification of login websites without needing to open item details.

3. **Full Interactive Sorting**
   - **Sort by URL**: Click the **URL** column header to sort vault items by domain / launch URI alphabetically (A–Z / Z–A).
   - **Sort by Name**: Fixes Web UI personal vault view where the Name column was statically rendered without sort capability.

4. **Automated APT Update Persistence (Debian / Ubuntu)**
   - Automatically maintains patches when `bitwarden` is updated via `apt upgrade` using APT Post-Invoke hooks.

---

## 🛠️ Quick Installation (Interactive Installer)

Clone this repository and run the unified installer:

```bash
git clone https://github.com/prostopasta/bitwarden-enhancer.git
cd bitwarden-enhancer
./install.sh
```

The installer will interactively prompt you for:
- **Target components**: Desktop client, Web Vault, or both.
- **Features to enable**:
  - `[x]` Persistent YubiKey biometric unlock
  - `[x]` URL column replacement
  - `[x]` Interactive sorting for URL and Name
- **Environment**:
  - Desktop client local auto-detection (`/opt/Bitwarden/resources/app.asar`).
  - Web Vault in **Docker container** (local or remote via SSH) or **host / VM directory**.

---

## 📖 Deployment Scenarios & Locations

### 1. Bitwarden Desktop on Linux (Host)
- **Where to run**: Directly on your Linux workstation where Bitwarden Desktop is installed.
- **Path**: Target file is `/opt/Bitwarden/resources/app.asar` (or `/usr/lib/bitwarden/resources/app.asar`).
- **Prerequisites**: `nodejs` / `npx` or `asar` (`npm i -g asar`).

```bash
./install.sh
# Select option 1 (Desktop Client)
```

### 2. Web Vault / Vaultwarden in Docker Container
- **Where to run**: On the Docker host (or remotely from your workstation over SSH).
- **Target**: The `vaultwarden` container (locates `/web-vault/app/main.*.js`).

```bash
./install.sh
# Select option 2 (Web Vault) -> Docker -> local container or remote SSH
```

### 3. Web Vault on Bare-Metal Host / VM / Static Web Server
- **Where to run**: Inside the VM or host serving the static web-vault assets (e.g. Nginx / Apache / Caddy document root).
- **Target path**: Root of the extracted Web Vault static files (containing `app/main.*.js` and `locales/`).

```bash
./install.sh
# Select option 2 (Web Vault) -> Local folder -> enter path e.g. /var/www/vaultwarden/web-vault
```

> **Note**: After patching Web Vault, perform a hard refresh in your browser (**Ctrl + F5** / **Shift + Reload**) to clear cached scripts.

---

## 📂 Repository Structure

```text
bitwarden-enhancer/
├── install.sh                       # Interactive unified installer with feature flags
├── README.md                        # Documentation and guides
├── LICENSE                          # GNU General Public License v3.0
├── patches/                         # Clean Git diff patches for upstream source code
│   ├── 01-linux-persistent-biometrics.patch
│   ├── 02-desktop-url-column-and-sort.patch
│   └── 03-web-vault-url-column-and-sort.patch
├── patches/                         # (see above, plus)
│   └── 04-desktop-compiled-biometrics.patch  # Same fix against the shipped bundle
└── scripts/                         # Standalone python patch engines
    ├── patch-desktop.py             # Renderer bundle patcher (URL column, sorting)
    ├── patch-biometrics-compiled.py # Applies 04-... to the main-process bundle
    ├── patch-web-vault.py           # Web Vault JS bundle patcher
    ├── repack-desktop-asar.sh       # Rebuild a patched app.asar for the installed version
    └── patch-bitwarden.sh           # APT Post-Invoke hook script
```

---

## 🔁 Surviving Package Upgrades

A saved patched `app.asar` belongs to the Bitwarden version it was built from. Copying it over a
newer build downgrades the client, so an upgrade needs the patch **rebuilt**, not restored:

```bash
sudo scripts/repack-desktop-asar.sh \
    --source /opt/Bitwarden/resources/app.asar \
    --output /tmp/app.asar.patched
```

The script extracts the installed asar, applies the patches and packs it back with
`--unpack-dir 'node_modules/@bitwarden/desktop-napi'`, refusing to hand over a result that lost the
biometrics marker or came back unchanged. It needs `python3` plus either `asar` or `npx`
(`npm i -g asar` avoids re-downloading `asar@3.2.0` on every run). Roughly 20 seconds on an SSD.

The two patch families age very differently, and the script treats them accordingly:

| Patch | Bundle | Anchors | On a new release |
|-------|--------|---------|------------------|
| Persistent biometrics | `main.js` (main process) | `class OsBiometricsServiceLinux`, `exports["default"] = ...` — **not** minified | Keeps applying; **required**, a miss fails the repack |
| URL column + sorting | `app/main.js` (renderer) | mangled ids like `a.bMT(2,1,"owner")`, `Cn.n.getLaunchUri` | Likely to miss after a webpack rebuild; reported, non-fatal (use `--require-all` to make it fatal) |

`patches/04-desktop-compiled-biometrics.patch` is the compiled counterpart of
`patches/01-linux-persistent-biometrics.patch`: the source patch needs the whole client rebuilt,
while this one applies to a bundle as shipped. A webpack bundle is a single enormous line, so
diffing the file is pointless — `patch-biometrics-compiled.py` slices the class block out, patches
that on its own with `patch(1)`, and splices it back.

Upstream 2026.8.0 already ships the scaffolding: the `Bitwarden_biometric` service name is
referenced elsewhere, and `enrollPersistent` / `hasPersistentKey` exist as stubs that do nothing and
return `false`. The patch fills them in and routes `getBiometricKey` through the Secret Service
first, which is what makes an unlock survive a restart. It touches only those hunks — upstream
comments and any unrelated edits to the class stay put.

Verified against Bitwarden 2026.8.0 (`Bitwarden-2026.8.0-amd64.deb`, sha256
`720ecc39…7bb415`): applying the patch to the pristine bundle produces exactly the block a working
patched install carries, re-running reports "already applied", and a full extract/patch/pack cycle
on the pristine asar takes ~11 s. On that release the renderer patches landed only partially — the
sorting comparator matched, the header and row patterns did not — which is the expected asymmetry.

### Unattended upgrades (Debian / Ubuntu)

`scripts/patch-bitwarden.sh` is the APT `Post-Invoke` hook. The variant maintained in
[prostopasta/dotfiles](https://github.com/prostopasta/dotfiles) (`bitwarden/patch-bitwarden.sh`)
goes further: it records the version a copy was built for in `app.asar.patched.version` and, when
the installed version moves ahead, calls `repack-desktop-asar.sh` to rebuild the copy instead of
restoring a stale one. Point it at this checkout with:

```bash
echo 'BW_ENHANCER_DIR=/path/to/bitwarden-enhancer' | sudo tee /etc/default/bitwarden-enhancer
```

If the rebuild fails, the hook leaves `app.asar` untouched — a client without biometrics beats a
broken one.

---

## ⚖️ License & Legal

This project is licensed under the **GNU General Public License v3.0** ([GPL-3.0](LICENSE)) in accordance with the upstream Bitwarden and Vaultwarden open-source licenses.

*Disclaimer: This is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Bitwarden, Inc.*

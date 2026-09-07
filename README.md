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
└── scripts/                         # Standalone python patch engines
    ├── patch-desktop.py             # Binary asar / JS patcher for Desktop
    ├── patch-web-vault.py           # Web Vault JS bundle patcher
    └── patch-bitwarden.sh           # APT Post-Invoke hook script
```

---

## ⚖️ License & Legal

This project is licensed under the **GNU General Public License v3.0** ([GPL-3.0](LICENSE)) in accordance with the upstream Bitwarden and Vaultwarden open-source licenses.

*Disclaimer: This is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Bitwarden, Inc.*

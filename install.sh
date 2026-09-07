#!/usr/bin/env bash
# ==============================================================================
# Bitwarden Ultimate Customizer: YubiKey Unlock & URL Column Enhancer
# Supports: Desktop Client (Linux/Debian/Ubuntu/Arch/Fedora) and Web Vault (Docker/Host/VM)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Bitwarden Enhancer: YubiKey Unlock & URL Column   ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

prompt_options() {
    echo -e "${YELLOW}Select components to patch:${NC}"
    echo "1) Desktop Client only (Local Linux App)"
    echo "2) Web Vault / Vaultwarden only (Docker, Host, VM)"
    echo "3) Both Desktop Client and Web Vault"
    read -rp "Enter choice [1-3] (default: 1): " target_choice
    target_choice="${target_choice:-1}"

    echo ""
    echo -e "${YELLOW}Select features to apply:${NC}"
    read -rp "Enable Persistent YubiKey Biometrics unlock? [Y/n]: " enable_yubikey
    enable_yubikey="${enable_yubikey:-y}"

    read -rp "Replace Owner column with URL column? [Y/n]: " enable_url
    enable_url="${enable_url:-y}"

    read -rp "Enable Interactive URL and Name column sorting? [Y/n]: " enable_sort
    enable_sort="${enable_sort:-y}"
}

patch_desktop() {
    echo -e "\n${BLUE}--> Patching Bitwarden Desktop Client...${NC}"
    
    local asar_path=""
    local candidates=(
        "/opt/Bitwarden/resources/app.asar"
        "/usr/lib/bitwarden/resources/app.asar"
        "/usr/share/bitwarden/resources/app.asar"
        "$HOME/.local/share/bitwarden/resources/app.asar"
    )

    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            asar_path="$c"
            break
        fi
    done

    if [[ -z "$asar_path" ]]; then
        read -rp "Enter absolute path to app.asar: " asar_path
        if [[ ! -f "$asar_path" ]]; then
            echo -e "${RED}Error: app.asar not found at '$asar_path'${NC}"
            return 1
        fi
    fi

    echo -e "Found asar at: ${GREEN}$asar_path${NC}"

    # Verify asar utility
    if ! command -v asar &>/dev/null && ! command -v npx &>/dev/null; then
        echo -e "${RED}Error: neither 'npx' nor 'asar' found. Please install nodejs/npm.${NC}"
        return 1
    fi

    local ASAR_CMD="npx asar@3.2.0"
    if command -v asar &>/dev/null; then
        ASAR_CMD="asar"
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/bw-desktop-patch-XXXXXX)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "Extracting app.asar..."
    $ASAR_CMD extract "$asar_path" "$tmp_dir"

    local py_flags=()
    [[ "$enable_url" =~ ^[Yy]$ ]] && py_flags+=("--url")
    [[ "$enable_sort" =~ ^[Yy]$ ]] && py_flags+=("--sort")
    [[ "$enable_yubikey" =~ ^[Yy]$ ]] && py_flags+=("--yubikey")

    python3 "$SCRIPT_DIR/scripts/patch-desktop.py" "$tmp_dir" "${py_flags[@]}"

    local out_asar="$tmp_dir/app.asar"
    echo "Repacking app.asar..."
    $ASAR_CMD pack "$tmp_dir" "$out_asar" --unpack-dir 'node_modules/@bitwarden/desktop-napi'

    echo "Creating backup at ${asar_path}.bak..."
    sudo cp -f "$asar_path" "${asar_path}.bak"
    sudo cp -f "$out_asar" "$asar_path"

    # Save copy for auto-update persistence hook
    local backup_dir="/opt/Bitwarden/custom-patch"
    if [[ -d "/opt/Bitwarden" ]]; then
        sudo mkdir -p "$backup_dir"
        sudo cp -f "$out_asar" "$backup_dir/app.asar.patched"
    fi

    # Install APT hook if on Debian/Ubuntu
    if [[ -d "/etc/apt/apt.conf.d" ]]; then
        read -rp "Install APT hook to automatically re-patch on 'apt upgrade'? [Y/n]: " install_apt_hook
        install_apt_hook="${install_apt_hook:-y}"
        if [[ "$install_apt_hook" =~ ^[Yy]$ ]]; then
            sudo cp -f "$SCRIPT_DIR/scripts/patch-bitwarden.sh" /usr/local/bin/patch-bitwarden.sh
            sudo chmod +x /usr/local/bin/patch-bitwarden.sh
            echo 'DPkg::Post-Invoke {"/usr/local/bin/patch-bitwarden.sh || true";};' | sudo tee /etc/apt/apt.conf.d/99bitwarden-patch >/dev/null
            echo -e "${GREEN}✓ Installed APT hook /etc/apt/apt.conf.d/99bitwarden-patch${NC}"
        fi
    fi

    echo -e "${GREEN}✓ Desktop Client successfully patched!${NC}"
    echo "Please restart Bitwarden Desktop."
}

patch_web_vault() {
    echo -e "\n${BLUE}--> Patching Web Vault (Vaultwarden / Bitwarden Web)...${NC}"
    echo "Where is Web Vault deployed?"
    echo "1) In Docker container (on this machine or accessible via SSH)"
    echo "2) Directly in a local folder (VM, bare metal, reverse proxy static root)"
    read -rp "Enter choice [1-2] (default: 1): " env_choice
    env_choice="${env_choice:-1}"

    local py_flags=()
    [[ "$enable_url" =~ ^[Yy]$ ]] && py_flags+=("--url")
    [[ "$enable_sort" =~ ^[Yy]$ ]] && py_flags+=("--sort")

    if [[ "$env_choice" == "1" ]]; then
        read -rp "Enter Docker container name (default: vaultwarden): " container_name
        container_name="${container_name:-vaultwarden}"

        read -rp "Is Docker on a remote host via SSH? [y/N]: " is_remote
        is_remote="${is_remote:-n}"

        if [[ "$is_remote" =~ ^[Yy]$ ]]; then
            read -rp "Enter SSH user@host (e.g. root@10.1.1.3): " ssh_target
            read -rp "Optional SSH identity file (e.g. ~/.ssh/id_rsa, leave blank for default): " ssh_key

            local ssh_cmd="ssh"
            [[ -n "$ssh_key" ]] && ssh_cmd="ssh -i $ssh_key"

            echo "Copying patch script to remote host..."
            local scp_cmd="scp"
            [[ -n "$ssh_key" ]] && scp_cmd="scp -i $ssh_key"
            $scp_cmd "$SCRIPT_DIR/scripts/patch-web-vault.py" "$ssh_target:/tmp/patch-web-vault.py"

            echo "Extracting main bundle from container..."
            $ssh_cmd "$ssh_target" "docker exec $container_name cat \$(docker exec $container_name find /web-vault/app -name 'main.*.js') > /tmp/web-main.js"
            $ssh_cmd "$ssh_target" "python3 /tmp/patch-web-vault.py /tmp/web-main.js ${py_flags[*]}"
            $ssh_cmd "$ssh_target" "docker cp /tmp/web-main.js $container_name:/web-vault/app/\$(docker exec $container_name basename \$(docker exec $container_name find /web-vault/app -name 'main.*.js'))"
            # Update cache-busting and ru messages
            $ssh_cmd "$ssh_target" "docker exec $container_name sed -i 's/\"message\": \"Владелец\"/\"message\": \"URL\"/g' /web-vault/locales/ru/messages.json 2>/dev/null || true"
            $ssh_cmd "$ssh_target" "docker exec $container_name sed -i 's/\.js?v=[0-9]*/.js?v=\$(date +%s)/g' /web-vault/index.html 2>/dev/null || true"
            $ssh_cmd "$ssh_target" "rm -f /tmp/patch-web-vault.py /tmp/web-main.js"
        else
            echo "Patching local Docker container: $container_name..."
            local main_file
            main_file="$(docker exec "$container_name" find /web-vault/app -name "main.*.js")"
            docker exec "$container_name" cat "$main_file" > /tmp/web-main.js
            python3 "$SCRIPT_DIR/scripts/patch-web-vault.py" /tmp/web-main.js "${py_flags[@]}"
            docker cp /tmp/web-main.js "$container_name:$main_file"
            docker exec "$container_name" sed -i 's/"message": "Владелец"/"message": "URL"/g' /web-vault/locales/ru/messages.json 2>/dev/null || true
            docker exec "$container_name" sed -i "s/\.js?v=[0-9]*/.js?v=$(date +%s)/g" /web-vault/index.html 2>/dev/null || true
            rm -f /tmp/web-main.js
        fi
    else
        read -rp "Enter directory containing web-vault (e.g. /var/www/web-vault): " vault_dir
        if [[ ! -d "$vault_dir" ]]; then
            echo -e "${RED}Error: directory '$vault_dir' not found.${NC}"
            return 1
        fi
        python3 "$SCRIPT_DIR/scripts/patch-web-vault.py" "$vault_dir" "${py_flags[@]}"
        sed -i 's/"message": "Владелец"/"message": "URL"/g' "$vault_dir/locales/ru/messages.json" 2>/dev/null || true
        sed -i "s/\.js?v=[0-9]*/.js?v=$(date +%s)/g" "$vault_dir/index.html" 2>/dev/null || true
    fi

    echo -e "${GREEN}✓ Web Vault successfully patched!${NC}"
    echo -e "Remember to hard-refresh browser (${YELLOW}Ctrl + F5${NC}) to clear cached scripts."
}

prompt_options

case "$target_choice" in
    1) patch_desktop ;;
    2) patch_web_vault ;;
    3) patch_desktop && patch_web_vault ;;
    *) echo -e "${RED}Invalid choice.${NC}"; exit 1 ;;
esac

echo -e "\n${GREEN}All selected tasks completed successfully!${NC}"

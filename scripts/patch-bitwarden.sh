#!/usr/bin/env bash
# APT Post-Invoke hook to re-apply patches after 'apt upgrade'
set -euo pipefail

ASAR_FILE="/opt/Bitwarden/resources/app.asar"
BACKUP_FILE="/opt/Bitwarden/resources/app.asar.bak"
SAVED_PATCHED="/opt/Bitwarden/custom-patch/app.asar.patched"

echo "=== Bitwarden Post-Update Auto-Patcher ==="

if [[ ! -f "$ASAR_FILE" ]]; then
    exit 0
fi

# If already patched, nothing to do
if grep -q "Bitwarden_biometric" "$ASAR_FILE" 2>/dev/null && grep -q "launchUri" "$ASAR_FILE" 2>/dev/null; then
    echo "✓ Bitwarden is already patched."
    exit 0
fi

if [[ -f "$SAVED_PATCHED" ]]; then
    echo "Restoring custom patched asar after package update..."
    cp -f "$ASAR_FILE" "$BACKUP_FILE"
    cp -f "$SAVED_PATCHED" "$ASAR_FILE"
    echo "✓ Custom patches restored."
    exit 0
fi

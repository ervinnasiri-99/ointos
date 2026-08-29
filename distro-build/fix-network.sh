#!/bin/bash
# ============================================================================
# fix-network.sh — bring up the OintOS live-session network.
#
# WHY: On VirtualBox/Hyper-V/QEMU, the OintOS live ISO boots with NetworkManager
# reporting the NIC as "strictly unmanaged" because Ubuntu 26.04's
# NetworkManager ships `[ifupdown] managed=false`, so it refuses to manage any
# device it thinks /etc/network/interfaces owns. dhclient is also not installed
# on 26.04. This script fixes it by:
#   1. Making NetworkManager manage the device (managed=true), and
#   2. As a robust fallback, configuring systemd-networkd (DHCP) which works
#      regardless of NM.
#
# Run as the live user (sudo is preconfigured passwordless in OintOS).
# ============================================================================
set -euo pipefail

echo "==> OintOS network fix"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "ERROR: nmcli not found — is NetworkManager installed?"
    exit 1
fi

# ---- 1. Make NetworkManager manage the ifupdown/considers-unmanaged device ---
if grep -q '\[ifupdown\]' /etc/NetworkManager/NetworkManager.conf; then
    echo "==> Setting [ifupdown] managed=true in NetworkManager.conf"
    sudo sed -i 's/^managed=.*$/managed=true/' /etc/NetworkManager/NetworkManager.conf \
        || sudo sed -i 's/\[ifupdown\]/[ifupdown]\nmanaged=true/' /etc/NetworkManager/NetworkManager.conf
fi

# Make sure managed=true is present under [ifupdown] even if the block was empty
if ! grep -A2 '\[ifupdown\]' /etc/NetworkManager/NetworkManager.conf | grep -q 'managed=true'; then
    echo "==> Adding managed=true under [ifupdown]"
    sudo sed -i 's/^\[ifupdown\]$/[ifupdown]\nmanaged=true/' /etc/NetworkManager/NetworkManager.conf
fi

# ---- 2. Also (robustly) configure systemd-networkd for DHCP fallback ---------
NET_FILE=/etc/systemd/network/20-enp0s3.network
echo "==> Writing systemd-networkd config to $NET_FILE"
sudo tee "$NET_FILE" >/dev/null <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

# ---- 3. Apply ----
sudo systemctl enable --now systemd-networkd 2>/dev/null || true
sudo systemctl restart systemd-networkd 2>/dev/null || true
sudo systemctl restart NetworkManager 2>/dev/null || true

sleep 3

# ---- 4. Find the ethernet device and try to connect it ----
ETH=$(nmcli -t device 2>/dev/null | awk -F: '$2=="ethernet"{print $1; exit}')
if [ -n "$ETH" ]; then
    echo "==> Bringing up $ETH via NetworkManager"
    sudo nmcli device set "$ETH" managed yes 2>/dev/null || true
    sudo nmcli device connect "$ETH" 2>/dev/null || true
    # Fallback through systemd-networkd path
    sudo ip link set "$ETH" up 2>/dev/null || true
fi

sleep 3

echo ""
echo "==> Result:"
ip -4 addr show 2>/dev/null | grep -E '^[0-9]+:|inet ' || echo "  (no IPv4 yet)"
echo ""
echo "==> Testing connectivity:"
if ping -c2 -W3 8.8.8.8 >/dev/null 2>&1; then
    echo "  INTERNET OK"
else
    echo "  no ping to 8.8.8.8 yet — trying DNS"
    getent hosts archive.ubuntu.com >/dev/null 2>&1 && echo "  DNS OK" || echo "  DNS not resolving"
fi
echo ""
nmcli device 2>/dev/null | head -5
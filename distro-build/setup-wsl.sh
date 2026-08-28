#!/bin/bash
set -euo pipefail

# OintOS WSL2 build-environment setup
#
# Run this INSIDE your WSL2 Ubuntu terminal on the Windows machine to
# prepare it for building the OintOS ISO.
#
#   cd ~/ointos/distro-build
#   ./setup-wsl.sh
#
# This script:
#   1. Checks for any ongoing apt processes and cleans locks
#   2. Installs the live-build prerequisites
#   3. Offers to create/update a .wslconfig to give WSL2 more memory
#   4. Verifies the tools work
#
# IMPORTANT: The repo should live INSIDE the WSL2 filesystem (e.g. ~/ointos),
# NOT on /mnt/c/... which is very slow for builds.

echo ""
echo "=== OintOS WSL2 Build Environment Setup ==="
echo ""

# --- Sanity check: are we in WSL? ------------------------------------------
if ! grep -qi microsoft /proc/version; then
    echo "WARNING: This does not look like a WSL environment."
    echo "         (continuing anyway — the tools are the same on native Ubuntu)"
    echo ""
fi

# --- Refuse to run from /mnt/c --------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
    /mnt/*)
        echo "ERROR: This script is being run from the Windows filesystem"
        echo "       ($SCRIPT_DIR)"
        echo ""
        echo "WSL2 builds are MUCH faster and more reliable inside the Linux"
        echo "filesystem. Please clone the repo into your WSL2 home and run"
        echo "from there:"
        echo ""
        echo "    cd ~"
        echo "    git clone https://github.com/ervinnasiri-99/ointos.git"
        echo "    cd ointos/distro-build"
        echo "    ./setup-wsl.sh"
        echo ""
        exit 1
        ;;
esac

# --- Wait for / fix dpkg locks if there's a stuck apt ----------------------
echo ">>> Checking for apt locks..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "    Another apt/dpkg process is running. Waiting 5s..."
    sleep 5
done

# --- Install prerequisites -------------------------------------------------
echo ">>> Updating package lists..."
sudo apt-get update

echo ">>> Installing live-build prerequisites..."
# Remove stale apt locks if any remain
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
sudo dpkg --configure -a 2>/dev/null || true

sudo apt-get install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    xorriso \
    genisoimage \
    grub-efi-amd64-bin \
    grub-pc-bin \
    mtools \
    dosfstools \
    git \
    python3 \
    qemu-utils \
    ovmf

echo ""
echo ">>> Verifying install..."
for tool in lb debootstrap mksquashfs xorriso genisoimage; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "    OK: $tool -> $(command -v $tool)"
    else
        echo "    MISSING: $tool"
    fi
done

# --- Offer .wslconfig update -----------------------------------------------
echo ""
echo ">>> WSL2 memory configuration"
MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_TOTAL_GB=$(( MEM_TOTAL_KB / 1024 / 1024 ))
echo "    WSL2 currently sees ${MEM_TOTAL_GB} GB RAM."
echo "    (Your Windows host should have 16 GB; WSL2 by default caps at 50%.)"
echo ""
echo "    WSL2 memory is limited by a .wslconfig file in your Windows user"
echo "    directory. To use 8 GB, create/edit it like this:"
echo ""
cat << 'EOF'
    ----- [Windows] C:\Users\<you>\.wslconfig -----
    [wsl2]
    memory=8GB
    processors=4
    swap=8GB
    ------------------------------------------------
EOF
echo ""
read -r -p "    Show a ready-to-copy .wslconfig block? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo ""
    echo "    Copy this into your Windows .wslconfig, then run 'wsl --shutdown'"
    echo "    and reopen WSL2:"
    echo ""
    echo "    [wsl2]"
    echo "    memory=8GB"
    echo "    processors=4"
    echo "    swap=8GB"
    echo ""
    read -r -p "    Open the .wslconfig in your editor? [y/N] " ans2
    if [[ "$ans2" =~ ^[Yy]$ ]]; then
        WSLUSER="${SUDO_USER:-$USER}"
        WINUSER_DIR="/mnt/c/Users"
        # Find the most likely user profile dir
        for d in "$WINUSER_DIR"/*/; do
            if [ -f "$d/.wslconfig" ]; then
                echo "    Found existing .wslconfig: $d"
                nano "$d/.wslconfig" 2>/dev/null || true
                break
            fi
        done
    fi
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next step — build the ISO:"
echo ""
echo "    cd ~/ointos/distro-build"
echo "    sudo python3 build.py"
echo ""
echo "(Full verbose log written to output/build-<timestamp>.log)"

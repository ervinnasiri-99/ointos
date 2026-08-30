#!/bin/bash
# ============================================================================
# OintOS calamares-settings installer
# Copies the OintOS Calamares branding + module configs into the right place
# on the live image (run inside the chroot during isobuild.sh).
#
#   - /etc/calamares/*.conf        module configs + settings.conf
#   - /usr/share/calamares/branding/ointos/  branding.desc, show.qml,
#     stylesheet.qss, img/
# ============================================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing OintOS Calamares settings..."

# 1. Module configs → /etc/calamares/
mkdir -p /etc/calamares
cp "$SRC"/modules/*.conf /etc/calamares/

# 2. Branding → /usr/share/calamares/branding/ointos/
mkdir -p /usr/share/calamares/branding/ointos
cp -r "$SRC/branding/." /usr/share/calamares/branding/ointos/

# 3. Landing logo (from OintOS branding if present at build, else skip)
if [ -f /workspace/branding/Oint.png ]; then
    mkdir -p /usr/share/calamares/branding/ointos/img
    cp /workspace/branding/Oint.png /usr/share/calamares/branding/ointos/img/logo.png
fi

echo "OintOS Calamares settings installed."
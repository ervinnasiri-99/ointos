#!/bin/bash
set -euo pipefail

# OintOS ISO Build Script
# Uses live-build to create a custom Ubuntu 26.04 + KDE Plasma ISO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"
DISTRO="resolute"
ARCH="amd64"
VERSION="1.0"

echo "=== OintOS ISO Builder ==="
echo "Distribution: Ubuntu $DISTRO ($ARCH)"
echo "Version: $VERSION"
echo ""

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

# Install prerequisites
echo ">>> Installing prerequisites..."
apt-get update
apt-get install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    xorriso \
    genisoimage \
    grub-efi-amd64-bin \
    grub-pc-bin \
    mtools \
    dosfstools \
    git

# Clean previous build
echo ">>> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
cd "$BUILD_DIR"

# Copy configuration
echo ">>> Copying configuration..."
cp -r "$SCRIPT_DIR/config/"* .

# Configure live-build
# NOTE: option names follow Ubuntu's live-build 3.0~a57 (see build.py for
# the rationale — --bootloader is singular; --security/--updates/--backports
# are not flags in this version).
echo ">>> Configuring live-build..."
lb config \
    --distribution "$DISTRO" \
    --architectures "$ARCH" \
    --archive-areas "main restricted universe multiverse" \
    --bootloader grub \
    --binary-images iso-hybrid \
    --memtest memtest86+ \
    --debian-installer false \
    --iso-application "OintOS" \
    --iso-publisher "OintOS Project" \
    --iso-volume "OintOS $VERSION" \
    --apt-indices false
    # apt-recommends kept ENABLED (default) so meta-packages pull a working KDE

# Build
echo ">>> Building ISO (this may take 30-90 minutes)..."
TIMESTAMP=$(date +%Y%m%d)
lb build 2>&1 | tee "$OUTPUT_DIR/build-$TIMESTAMP.log"

# Move and rename output
ISO_NAME="OintOS-${VERSION}-${ARCH}-${TIMESTAMP}.iso"
mv live-image-*.iso "$OUTPUT_DIR/$ISO_NAME"

# Generate checksum
cd "$OUTPUT_DIR"
sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"

echo ""
echo "=== Build Complete ==="
echo "ISO: $OUTPUT_DIR/$ISO_NAME"
echo "SHA256: $OUTPUT_DIR/$ISO_NAME.sha256"
echo "Log: $OUTPUT_DIR/build-$TIMESTAMP.log"
echo ""
echo "Test with: qemu-system-x86_64 -cdrom $OUTPUT_DIR/$ISO_NAME -m 4096 -enable-kvm"

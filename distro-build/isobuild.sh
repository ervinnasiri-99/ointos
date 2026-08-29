#!/bin/bash
# ============================================================================
# OintOS ISO Builder — manual debootstrap + casper + custom-GRUB pipeline
#
# This REPLACES the live-build pipeline (see docs/decisions/004-build-pipeline-
# casper.md). Ubuntu 26.04's live-build is broken for custom ISOs (Bug 2154055:
# --bootloader grub wants 'grub-legacy', syslinux wants packages from 11.10),
# so we build the ISO by hand, modeled on Ubuntu's own livecd-rootfs and the
# proven recipe in Utile-OS (github.com/Proman4713/Utile-OS, GH-Actions-passing
# Ubuntu 26.04 ISO).
#
# Run inside a root-capable environment (WSL2 Ubuntu on the Ryzen machine, or
# a Docker ubuntu:26.04 container). Needs ~25 GB free.
#
#   sudo bash isobuild.sh
#
# Output: output/OintOS-<version>-amd64-<date>.iso
# ============================================================================
set -exuo pipefail
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# ---------------------------------------------------------------------------
# Configuration (tweak here)
# ---------------------------------------------------------------------------
OINTOS_VERSION="${OINTOS_VERSION:-1.0}"
DISTRO="resolute"                 # Ubuntu 26.04 LTS codename
ARCH="amd64"
WORK_DIR="${OINTOS_WORK_DIR:-/opt/ointos-build}"
ISO_NAME="OintOS-${OINTOS_VERSION}-${ARCH}"

# ---------------------------------------------------------------------------
# Guaranteed cleanup: whatever happens (error, Ctrl+C, success), release every
# mount under WORK_DIR from the HOST side. This is what keeps the build from
# leaving stale mounts that can corrupt a WSL2 host's systemd/devfs on the next
# wsl --shutdown. Runs on EXIT (also covers ERR because of set -e).
# ---------------------------------------------------------------------------
cleanup_mounts() {
    for _ in $(seq 1 20); do
        mp=$(awk -v c="$WORK_DIR/" 'index($2, c) == 1 { if (length($0)>max){max=length($0); best=$2} } END{print best}' /proc/self/mounts)
        [ -z "$mp" ] && break
        echo "   [cleanup] unmounting: $mp"
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done
}
trap cleanup_mounts EXIT

# KDE Plasma desktop + OintOS tooling (APT-first; no snaps in v1)
PACKAGES_DESKTOP="
kde-plasma-desktop
plasma-workspace
kde-spectacle
dolphin
konsole
kate
okular
gwenview
ark
kwalletmanager
sddm
sddm-theme-breeze
plasma-nm
powerdevil
systemsettings
network-manager
"
PACKAGES_SYSTEM="
ubuntu-standard
btrfs-progs
timeshift
htop
inxi
git
curl
wget
parted
gparted
rsync
psmisc
file
xz-utils
ca-certificates
gnupg
"

# ---------------------------------------------------------------------------
# Chroot helpers (from livecd-rootfs / Utile-OS recipe)
# ---------------------------------------------------------------------------

setup_chroot() {
    # Mount host dirs into the chroot so apt/initramfs work.
    # mkdir -p: after an overlay mount, /dev, /proc, /sys, /run may not exist
    # as visible dirs in the merged view (e.g. if the base chroot lacks them
    # or the lowerdir was stripped) — bind-mounting onto a missing target
    # fails ("mount point does not exist").
    for d in dev dev/pts proc sys run; do
        mkdir -p "$1/$d"
    done
    mount --bind /dev "$1/dev"
    mount --bind /dev/pts "$1/dev/pts"
    mount -t proc /proc "$1/proc"
    mount -t sysfs /sys "$1/sys"
    mount --bind /run "$1/run"
    rm -f "$1/etc/resolv.conf"
    cp -L /etc/resolv.conf "$1/etc/resolv.conf"
}

wrapup_chroot() {
    # Restore resolv.conf, unmount everything
    rm -f "$1/etc/resolv.conf"
    chroot "$1" /bin/bash -c "ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf"
    umount --lazy "$1/run" 2>/dev/null || true
    umount --lazy "$1/sys" 2>/dev/null || true
    umount --lazy "$1/proc" 2>/dev/null || true
    umount --lazy "$1/dev/pts" 2>/dev/null || true
    umount --lazy "$1/dev" 2>/dev/null || true
}

# initramfs-tools casper config (from livecd-rootfs internals)
initramfstools_casper_gen="mkdir -p etc/initramfs-tools/conf.d
cat > etc/initramfs-tools/conf.d/casperize.conf <<EOF
export CASPER_GENERATE_UUID=1
export LAYERFS_PATH=filesystem.squashfs
EOF
cat > etc/initramfs-tools/conf.d/default-layer.conf <<EOF
LAYERFS_PATH=filesystem.squashfs
EOF
update-initramfs -c -k all"

# ---------------------------------------------------------------------------
# 0. Host prerequisites
# ---------------------------------------------------------------------------
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo ">>> Installing host build tools..."
apt-get update
apt-get install -y --no-install-recommends \
    cpio \
    debootstrap \
    dosfstools \
    grub-common \
    grub-efi-amd64-bin \
    grub-pc-bin \
    initramfs-tools-core \
    mtools \
    squashfs-tools \
    syslinux-utils \
    tree \
    ubuntu-keyring \
    xorriso

# ---------------------------------------------------------------------------
# 1. Bootstrap base chroot
# ---------------------------------------------------------------------------
CHROOT_DIR="$WORK_DIR/chroot"
if [ -d "$CHROOT_DIR" ]; then
    echo ">>> Cleaning previous chroot..."
    # Unmount anything still mounted under the chroot, FROM THE HOST (a
    # chroot-internal umount can't release host bind mounts like
    # /run/credentials/* or /run/snapd/ns/*). Loop until nothing matches.
    for _ in $(seq 1 20); do
        # Locate the deepest host mount whose mountpoint is under CHROOT_DIR.
        mp=$(awk -v c="$CHROOT_DIR/" 'index($2, c) == 1 { if (length($0)>max){max=length($0); best=$2} } END{print best}' /proc/self/mounts)
        [ -z "$mp" ] && break
        echo "    unmounting: $mp"
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done
    # Now it should be safe to remove.
    rm -rf "$CHROOT_DIR" 2>/dev/null || { sleep 2; rm -rf "$CHROOT_DIR" 2>/dev/null; }
    if [ -d "$CHROOT_DIR" ]; then
        echo "WARNING: could not fully remove $CHROOT_DIR (some mounts busy) — continuing"
    fi
fi
mkdir -p "$CHROOT_DIR"

echo ">>> debootstrap $DISTRO (base system)..."
debootstrap \
    --arch="$ARCH" \
    --components=main,restricted,universe,multiverse \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --verbose \
    "$DISTRO" \
    "$CHROOT_DIR" \
    http://archive.ubuntu.com/ubuntu

setup_chroot "$CHROOT_DIR"

# Write the OintOS identity directly into the chroot (host-side: $OINTOS_VERSION
# expands here; it is NOT passed into the chroot). Placeholder branding — Phase 14.
cat > "$CHROOT_DIR/etc/os-release" <<OS_RELEASE_EOF
PRETTY_NAME="OintOS ${OINTOS_VERSION}"
NAME="OintOS"
VERSION_ID="${OINTOS_VERSION}"
VERSION="${OINTOS_VERSION} (Resolute Raccoon)"
VERSION_CODENAME=resolute
ID=ointos
ID_LIKE=ubuntu
HOME_URL="https://github.com/ervinnasiri-99/ointos"
BUG_REPORT_URL="https://github.com/ervinnasiri-99/ointos/issues"
OS_RELEASE_EOF

# ---------------------------------------------------------------------------
# 2. Install OintOS packages into the base chroot
# ---------------------------------------------------------------------------
cat > "$CHROOT_DIR/opt/install-base.sh" <<'OINTOS_EOF'
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# The version is baked into /etc/os-release by the host script before this
# runs (util-linux chroot has no env-inheritance flag). Nothing to set here.

# Default repos already point at resolute via debootstrap; enable all areas
cat > /etc/apt/sources.list <<SOURCES_EOF
deb http://archive.ubuntu.com/ubuntu resolute main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu resolute-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu resolute-security main restricted universe multiverse
SOURCES_EOF

apt-get update
apt-get install -y --no-install-recommends \
    linux-generic \
    linux-image-generic \
    linux-headers-generic \
    initramfs-tools \
    squashfs-tools \
    btrfs-progs \
    ubuntu-standard \
    openntpd \
    locales

# Desktop environment
apt-get install -y \
    kde-plasma-desktop \
    plasma-workspace \
    kde-spectacle \
    dolphin \
    konsole \
    kate \
    okular \
    gwenview \
    ark \
    kwalletmanager \
    sddm \
    sddm-theme-breeze \
    plasma-nm \
    powerdevil \
    systemsettings \
    network-manager

# OintOS system tools
apt-get install -y \
    timeshift \
    htop \
    inxi \
    git \
    curl \
    wget \
    parted \
    gparted \
    rsync \
    psmisc \
    file \
    xz-utils \
    ca-certificates \
    gnupg

# Default browser: Ubuntu 26.04 ships 'firefox' (the ESR snap name
# 'firefox-esr' does not exist in archive) — verified against
# packages.ubuntu.com/resolute via Playwright.
# Phase 4 will swap this for Brave per the master prompt.
apt-get install -y \
    firefox \
    vim \
    nano \
    htop

# Set up locale + hostname + user
sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
echo "ointos" > /etc/hostname
useradd -m -s /bin/bash -G sudo oinstaller 2>/dev/null || true
echo "oinstaller:ointos" | chpasswd

# Zero telemetry (per master prompt — by architecture, not default)
systemctl disable apport.service 2>/dev/null || true
systemctl disable whoopsie.service 2>/dev/null || true
systemctl disable ubuntu-report.service 2>/dev/null || true
rm -f /etc/apport/crashdb.conf
rm -rf /var/lib/apport /var/crash 2>/dev/null || true
mkdir -p /var/crash
chmod 700 /var/crash
# Disable Ubuntu Pro / MOTD that phones home
rm -f /etc/update-motd.d/50-motd-news 2>/dev/null || true
echo "OintOS: telemetry disabled by architecture"

# Clean up apt lists to shrink the image
apt-get clean
rm -rf /var/lib/apt/lists/*
OINTOS_EOF

chmod +x "$CHROOT_DIR/opt/install-base.sh"
chroot "$CHROOT_DIR" /bin/bash -lc "/opt/install-base.sh"
rm -f "$CHROOT_DIR/opt/install-base.sh"

wrapup_chroot "$CHROOT_DIR"

# ---------------------------------------------------------------------------
# 3. Create the live layer (casper) and regenerate initramfs
# ---------------------------------------------------------------------------
MERGED_DIR="$WORK_DIR/merged"
mkdir -p "$WORK_DIR/live-upper" "$WORK_DIR/live-work" "$MERGED_DIR"

# If a previous run failed after mounting the overlay, unmount host-side so
# the fresh overlay mount below won't fail (EBUSY).
for _ in $(seq 1 10); do
    mp=$(awk -v c="$MERGED_DIR/" 'index($2, c) == 1 { if (length($0)>max){max=length($0); best=$2} } END{print best}' /proc/self/mounts)
    [ -z "$mp" ] && break
    echo "    unmounting stale: $mp"
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
done

mount -t overlay overlay \
    -o lowerdir="$CHROOT_DIR",upperdir="$WORK_DIR/live-upper",workdir="$WORK_DIR/live-work" \
    "$MERGED_DIR"

setup_chroot "$MERGED_DIR"

cat > "$MERGED_DIR/opt/live-setup.sh" <<'OINTOS_EOF'
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# casper + initramfs-tools are required to boot from the squashfs
apt-get update
apt-get install -y casper \
    cryptsetup \
    cryptsetup-bin \
    cryptsetup-initramfs \
    initramfs-tools

apt-get autoremove -y --purge
apt-get purge -y '~c' || true
apt-get clean

# Regenerate initramfs with casper layer support
mkdir -p /etc/initramfs-tools/conf.d
cat > /etc/initramfs-tools/conf.d/casperize.conf <<EOF
export CASPER_GENERATE_UUID=1
export LAYERFS_PATH=filesystem.squashfs
EOF
cat > /etc/initramfs-tools/conf.d/default-layer.conf <<EOF
LAYERFS_PATH=filesystem.squashfs
EOF
update-initramfs -c -k all
OINTOS_EOF

chmod +x "$MERGED_DIR/opt/live-setup.sh"
chroot "$MERGED_DIR" /bin/bash -lc "/opt/live-setup.sh"
rm -f "$MERGED_DIR/opt/live-setup.sh"

wrapup_chroot "$MERGED_DIR"

# ---------------------------------------------------------------------------
# 4. Extract kernel + initrd, make squashfs
# ---------------------------------------------------------------------------
VMLINUZ=$(ls -1 "$MERGED_DIR/boot/vmlinuz-"* | tail -n 1)
INITRD=$(ls -1 "$MERGED_DIR/boot/initrd.img-"* | tail -n 1)
echo ">>> Using kernel: $VMLINUZ"
echo ">>> Using initrd: $INITRD"

# Clean the live layer of mount points before squashfs
rm -rf "$MERGED_DIR/dev" "$MERGED_DIR/proc" "$MERGED_DIR/sys" "$MERGED_DIR/run" 2>/dev/null || true

ISODIR="$WORK_DIR/custom-iso"
rm -rf "$ISODIR" && mkdir -p "$ISODIR/casper"
cp "$VMLINUZ" "$ISODIR/casper/vmlinuz"
cp "$INITRD"  "$ISODIR/casper/initrd"

# Single merged squashfs (standard casper live layout)
mksquashfs "$MERGED_DIR" "$ISODIR/casper/filesystem.squashfs" -comp xz -noappend

# Casper metadata.
# CRITICAL: install-sources.yaml must be the YAML-*list* format that Ubuntu's
# subiquity/casper tooling parses (each source is "- ..."), NOT a top-level
# kernel:/sources: map — a malformed file was implicated in casper failing to
# resolve the squashfs. Format verified against AskUbuntu "Minimal Ubuntu
# Install" (livecd-rootfs generated live ISOs).
FILESYSTEM_SIZE=$(du -sx --block-size=1 "$MERGED_DIR" | cut -f1)
printf '%s' "$FILESYSTEM_SIZE" > "$ISODIR/casper/filesystem.size"

# filesystem.manifest (what casper/live detection reads to know it's a live CD)
chroot "$MERGED_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' \
    | sort > "$ISODIR/casper/filesystem.manifest"

cat > "$ISODIR/casper/install-sources.yaml" <<YAML_EOF
- default: true
  description:
    en: OintOS (KDE Plasma)
  id: ointos-desktop
  locale_support: langpack
  name:
    en: Standard
  path: filesystem.squashfs
  size: $FILESYSTEM_SIZE
  type: fsimage
  variant: desktop
YAML_EOF

# ---------------------------------------------------------------------------
# 5. .disk/, ubuntu symlink, grub overlay, EFI
# ---------------------------------------------------------------------------
mkdir -p "$ISODIR/.disk"
ln -s . "$ISODIR/ubuntu"
touch "$ISODIR/.disk/base_installable"
echo "full_cd/single" > "$ISODIR/.disk/cd_type"

# ****************************************************************************
# CRITICAL: .disk/casper-uuid-generic
#   casper's check_dev() mounts the ISO, finds /casper/*.squashfs (is_casper_path
#   PASSES), then REQUIRES the device's UUID to match the initrd's generated
#   UUID ($UUID from conf/uuid.conf) via matches_uuid(). That looks for a file
#   named .disk/casper-uuid-* in the ISO root. WITHOUT it, casper rejects the
#   medium: "Unable to find a medium containing a live file system".
#
#   Verified in a QEMU initramfs trace (find_livefs): is_casper_path=0, then
#   UUID gate fails because the ISO has no .disk/casper-uuid-generic. This was
#   the root cause of our boot failure (not install-sources.yaml).
#
#   Extract the UUID from the initrd and write it to the ISO, exactly as
#   Utile-OS/livecd-rootfs do.
# ****************************************************************************
INITRD_DIR="$WORK_DIR/extracted-initrd"
rm -rf "$INITRD_DIR" && mkdir -p "$INITRD_DIR"
unmkinitramfs "$ISODIR/casper/initrd" "$INITRD_DIR"
UUID_CONF=$(find "$INITRD_DIR" -type f \( -path "*/conf/uuid.conf" -o -name "uuid.conf" \) | head -n 1)
if [ -n "$UUID_CONF" ]; then
    echo "extracted initrd UUID from $UUID_CONF"
    mv "$UUID_CONF" "$ISODIR/.disk/casper-uuid-generic"
else
    echo "WARNING: uuid.conf not found in initrd — casper UUID check may fail"
fi
rm -rf "$INITRD_DIR"

# Write the GRUB config (casper live entries) — manual, avoids live-build bug
mkdir -p "$ISODIR/boot/grub"
cat > "$ISODIR/boot/grub/grub.cfg" <<'GRUB_EOF'
set timeout=10

loadfont unicode
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Try OintOS" {
    set gfxpayload=keep
    linux /casper/vmlinuz --- boot=casper quiet splash
    initrd /casper/initrd
}

menuentry "Try OintOS (safe graphics)" {
    set gfxpayload=keep
    linux /casper/vmlinuz nomodeset --- boot=casper quiet splash
    initrd /casper/initrd
}

if [ "$grub_platform" = "efi" ]; then
    menuentry "Boot from next volume" {
        exit 1
    }
    menuentry "UEFI Firmware Settings" {
        fwsetup
    }
fi
GRUB_EOF

# Official GRUB modules + EFI boot images from Ubuntu packages
mkdir -p /tmp/uefi-images
cd /tmp/uefi-images || exit 1
apt-get download shim-signed grub-efi-amd64-signed grub-pc-bin grub-efi-amd64-bin grub2-common 2>/dev/null
for deb in *.deb; do [ -f "$deb" ] && dpkg -x "$deb" .; done

# boot/grub modules (BIOS + EFI)
mkdir -p "$ISODIR/boot/grub/x86_64-efi/"
find /tmp/uefi-images/usr/lib/grub/x86_64-efi/ -type f \( -name "*.lst" -o -name "*.mod" \) -print0 2>/dev/null \
    | xargs -0 -r cp -t "$ISODIR/boot/grub/x86_64-efi/"
mkdir -p "$ISODIR/boot/grub/i386-pc/"
cp -r /tmp/uefi-images/usr/lib/grub/i386-pc/. "$ISODIR/boot/grub/i386-pc/" 2>/dev/null || true

# fonts
mkdir -p "$ISODIR/boot/grub/fonts"
cp /usr/share/grub/unicode.pf2 "$ISODIR/boot/grub/fonts" 2>/dev/null || true

# EFI/boot (shim + grub)
mkdir -p "$ISODIR/EFI/boot"
cp /tmp/uefi-images/usr/lib/shim/shimx64.efi.signed.latest "$ISODIR/EFI/boot/bootx64.efi" 2>/dev/null || true
cp /tmp/uefi-images/usr/lib/shim/mmx64.efi "$ISODIR/EFI/boot/mmx64.efi" 2>/dev/null || true
cp /tmp/uefi-images/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed "$ISODIR/EFI/boot/grubx64.efi" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. EFI partition image + md5sum
# ---------------------------------------------------------------------------
EFI_SIZE=$(($(du -s --apparent-size --block-size=1024 "$ISODIR/EFI/" | cut -f1) + 1024))
mkfs.msdos -n OINTOS-ESP -C /tmp/efi.img "$EFI_SIZE"
mcopy -s -i /tmp/efi.img "$ISODIR/EFI/" ::/.

(cd "$ISODIR" && find . -type f ! -name "md5sum.txt" ! -name "eltorito.img" ! -name "grub.cfg" -print0 | sort -z | xargs -0 md5sum > "$ISODIR/md5sum.txt")

# ---------------------------------------------------------------------------
# 7. Assemble the hybrid ISO (BIOS grub-mbr + EFI appended partition)
# ---------------------------------------------------------------------------
mkdir -p "$WORK_DIR/output"
set +e
xorriso -as mkisofs \
    -iso-level 3 \
    -J -joliet-long \
    -full-iso9660-filenames \
    -volid "OintOS ${OINTOS_VERSION} amd64" \
    --mbr-force-bootable \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /tmp/uefi-images/usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -partition_offset 16 \
    -append_partition 2 0xef /tmp/efi.img \
    -appended_part_as_gpt \
    -c boot.catalog \
    -o "$WORK_DIR/output/$ISO_NAME.iso" \
    "$ISODIR"
set -e

echo ">>> Generating SHA-256..."
(cd "$WORK_DIR/output" && sha256sum "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256")

echo ""
echo "==========================================================="
echo "  BUILD COMPLETE"
echo "  ISO:  $WORK_DIR/output/$ISO_NAME.iso"
echo "  SHA:  $WORK_DIR/output/$ISO_NAME.iso.sha256"
echo "  Size: $(du -h --block-size=1M "$WORK_DIR/output/$ISO_NAME.iso" | cut -f1)M"
echo "==========================================================="
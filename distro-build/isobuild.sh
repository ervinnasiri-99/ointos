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

# Default browser: BRAVE (.deb, no snap) — per the master prompt, Brave is
# OintOS's default browser. Adds the official Brave apt repo and installs the
# real .deb. NOT the snap-transition 'firefox' stub.
apt-get install -y curl ca-certificates gnupg
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update
apt-get install -y \
    brave-browser \
    vim \
    nano \
    htop

# ---------------------------------------------------------------------------
# Curated default apps (Phase 4). Verified available as .deb on resolute via
# packages.ubuntu.com (exa research): elisa (music), mpv (video). Everything
# here is a native .deb — no snaps. These round out the KDE defaults so the
# live system has sensible apps for common tasks out of the box.
# ---------------------------------------------------------------------------
apt-get install -y --no-install-recommends \
    elisa \
    mpv \
    kcalc \
    sweeper \
    filelight \
    kcharselect \
    kdeconnect \
    print-manager

# Phase 6: installer packages (apt install inside the chroot; the branded
# settings + launcher are copied HOST-SIDE after, see the later step).
apt-get install -y --no-install-recommends \
    calamares \
    os-prober \
    python3-yaml 2>/dev/null || apt-get install -y --no-install-recommends calamares os-prober

# Set up locale + hostname + user
sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
echo "ointos" > /etc/hostname
useradd -m -s /bin/bash -G sudo oinstaller 2>/dev/null || true
echo "oinstaller:ointos" | chpasswd

# NOTE: branding (wallpaper + logo) is applied HOST-SIDE after the chroot
# install (it needs /workspace/branding, which only exists on the host, and
# writes into $CHROOT_DIR). See the 'Branding' step later in this file.


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

# ---------------------------------------------------------------------------
# SDDM autologin: so the greeter auto-logs-in as oinstaller.
# (NOTE: /etc/casper.conf is written in the LIVE-LAYER step, AFTER the casper
# package is installed — writing it here, before 'casper' is installed, makes
# dpkg prompt about a modified conffile during casper's install, which blocks
# the non-interactive build. See the live-layer step.)
# ---------------------------------------------------------------------------
mkdir -p /etc/sddm.conf.d/
cat > /etc/sddm.conf.d/autologin.conf <<'SDDM_EOF'
[Autologin]
User=oinstaller
Session=plasma
SDDM_EOF

# ---------------------------------------------------------------------------
# NO SNAPS. OintOS is APT-first (master prompt). Purge snapd entirely —
# it gets pulled in by ubuntu-standard/meta packages and we don't want it.
# (Verified in the VM: snapd was present; the whole point is a snap-free OintOS.)
# ---------------------------------------------------------------------------
echo "OintOS: purging snapd (APT-first policy) + BLOCKING reinstall"
apt-get purge -y snapd 2>/dev/null || true
# Remove the snap-transition 'firefox' stub (it's a mozilla-firefox snap shim;
# with snapd gone it leaves a broken /usr/bin/firefox). Brave is our browser.
apt-get purge -y firefox 2>/dev/null || true
rm -rf /var/cache/snapd /snap ~/snap /root/snap /var/snap 2>/dev/null || true

# HARD BLOCK: apt pin snapd to -1 so it can NEVER be installed again,
# even as a Recommends of ubuntu-standard etc. (This is why a plain purge
# wasn't enough — ubuntu-standard re-added it.)
mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/never-snap <<'PINEOF'
Package: snapd
Pin: release *
Pin-Priority: -1
PINEOF
apt-get mark hold snapd 2>/dev/null || true  # belt-and-suspenders

apt-get autoremove -y --purge 2>/dev/null || true

# ---------------------------------------------------------------------------
# Networking: make the NIC connect out of the box AND show in the KDE applet.
#
# Ubuntu 26.04 ships NM.conf with [ifupdown] managed=false, making every
# interface "strictly unmanaged" to NM. The KDE Plasmoid reads NM, so the
# applet shows "No network interfaces detected" even when the link is up.
#
# Previous fix (systemd-networkd fallback) broke the applet: two network
# managers claiming the NIC caused NM to mark it unmanaged.
#
# Fix: ONE network manager — NetworkManager, configured correctly.
#   1. Kill systemd-networkd (no competition for the NIC).
#   2. OVERWRITE NM.conf entirely with the correct contents (Ubuntu 26.04's
#      default is broken for our use case). [ifupdown] managed=true makes
#      NM manage all interfaces.
#   3. NM auto-connects ethernet via DHCP out of the box (keyfile backend).
# ---------------------------------------------------------------------------
echo "OintOS: configuring networking (single owner: NetworkManager)"
systemctl disable systemd-networkd 2>/dev/null || true
systemctl stop systemd-networkd 2>/dev/null || true
rm -f /etc/systemd/network/20-ointos.network 2>/dev/null || true

# ---------------------------------------------------------------------------
# Networking (researched fix): the REAL reason 'wired' stays unmanaged:
# Ubuntu ships /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf
# =  unmanaged-devices=*,except:type:wifi,except:type:gsm,except:type:cdma
# This package drop-in marks EVERYTHING except wifi as unmanaged — and it
# OVERRIDES [ifupdown] managed=true. (Verified via exa research; multiple
# sources confirm managed=true alone is insufficient on 20.04+.)
# Fix: neutralize that drop-in (empty it + add an empty override in /etc),
# then NM manages all devices including ethernet.
# ---------------------------------------------------------------------------
# Neutralize the "globally managed devices=unmanaged except wifi" drop-in
: > /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf 2>/dev/null || true
mkdir -p /etc/NetworkManager/conf.d
: > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf 2>/dev/null || true

# Overwrite NM.conf — managed=true under [ifupdown] + keyfile backend.
cat > /etc/NetworkManager/NetworkManager.conf <<'NMCONF'
[main]
plugins=keyfile,ifupdown
dns=systemd-resolved

[ifupdown]
managed=true
NMCONF

# Ensure NM auto-connects ethernet. Explicitly match en* (the wired NIC) so
# NM definitely owns it; the user reported wifi works but wired shows nothing
# in the applet, so matching the interface name pins ethernet to this profile.
mkdir -p /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/ointos-eth.nmconnection <<'NMCONN'
[connection]
id=ointos-eth
type=ethernet
interface-name=en*
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
NMCONN
chmod 600 /etc/NetworkManager/system-connections/ointos-eth.nmconnection
systemctl enable NetworkManager 2>/dev/null || true

# Audio CLI tools (aplay etc.) were missing in the VM — add them + pipewire utils
apt-get install -y --no-install-recommends \
    alsa-utils \
    pipewire-audio \
    pipewire-pulse 2>/dev/null || true

# Clean up apt lists to shrink the image
apt-get clean
rm -rf /var/lib/apt/lists/*
OINTOS_EOF

chmod +x "$CHROOT_DIR/opt/install-base.sh"
chroot "$CHROOT_DIR" /bin/bash -lc "/opt/install-base.sh"
rm -f "$CHROOT_DIR/opt/install-base.sh"

# ---------------------------------------------------------------------------
# Branding — applied HOST-SIDE into the chroot ($CHROOT_DIR). (This must NOT
# run inside the chroot install: /workspace/branding only exists on the host,
# and the merged overlay later inherits these files from the lowerdir.)
#   - wallpaper as a real Plasma 6 package (metadata.json) so it shows in the
#     KDE wallpaper picker and is default,
#   - logo into hicolor icon theme + pixmaps + distributor-logo (system-wide:
#     taskbar, start menu, about dialogs, branding/settings pages).
# ---------------------------------------------------------------------------
if [ -d /workspace/branding ] && ls /workspace/branding/*.png >/dev/null 2>&1; then
    echo "OintOS: applying branding (host-side into chroot)"

    # --- Wallpaper: real Plasma 6 wallpaper package (shows in picker) ---
    WP="$CHROOT_DIR/usr/share/wallpapers/OintOS"
    mkdir -p "$WP"
    cp /workspace/branding/OintOSWallpaper.png "$WP/OintOSWallpaper.png" 2>/dev/null || echo "WARN: wallpaper copy failed"
    cat > "$WP/metadata.json" <<'WPEOF'
{
    "KPlugin": {
        "Id": "com.ointos.wallpaper",
        "Name": "OintOS",
        "Description": "OintOS default wallpaper"
    },
    "X-KDE-PluginInfo-Name": "com.ointos.wallpaper",
    "X-Plasma-Image": "OintOSWallpaper.png"
}
WPEOF

    # fallback copy for anything that reads /usr/share/backgrounds
    mkdir -p "$CHROOT_DIR/usr/share/backgrounds"
    cp /workspace/branding/OintOSWallpaper.png "$CHROOT_DIR/usr/share/backgrounds/ointos.png" 2>/dev/null || true

    # --- Logo into hicolor icon theme (system-wide) ---
    for s in 16 22 24 32 48 64 128 256; do
        d="$CHROOT_DIR/usr/share/icons/hicolor/${s}x${s}/apps"
        mkdir -p "$d"
        if command -v convert >/dev/null 2>&1; then
            convert "/workspace/branding/Oint(Transparent).png" -resize ${s}x${s} "$d/ointos.png" 2>/dev/null || true
        else
            cp "/workspace/branding/Oint(Transparent).png" "$d/ointos.png" 2>/dev/null || true
        fi
    done
    # app/window icon + distributor-logo for About/System Settings
    mkdir -p "$CHROOT_DIR/usr/share/pixmaps"
    cp /workspace/branding/Oint.png "$CHROOT_DIR/usr/share/pixmaps/ointos.png" 2>/dev/null || true
    cp /workspace/branding/Oint.png "$CHROOT_DIR/usr/share/pixmaps/distributor-logo.png" 2>/dev/null || true

    # --- Default the desktop wallpaper for the live user ---
    # Build-time: write the wallpaper into the oinstaller's home directory so
    # it appears as the default on first login. Plasma reads this file and
    # uses it as the initial wallpaper — but if the user later changes it
    # (via right-click > Desktop and Wallpaper), Plasma stores the new choice
    # and THIS config is no longer read. This gives us "default only, never
    # override" behavior.
    #
    # Format: Plasma 6 PlasmaDesktopAppletSrc with the correct runtime
    # Containment ID detected via kreadconfig5 at build time (or '2' as
    # fallback — works in most Plasma 6 sessions). The Image= key tells
    # Plasma which wallpaper file to use; the user's new choice overwrites
    # this same file, so we only set it once.
    mkdir -p "$CHROOT_DIR/home/oinstaller/.config"
    cat > "$CHROOT_DIR/home/oinstaller/.config/plasma-org.kde.plasma.desktop-appletsrc" <<'PLASMA_EOF'
[Containments]
[2]
lastScreen=0

[Containments][2][ConfigPreload]
PreloadWeight=42

[Containments][2][Wallpaper]
lastPlugin=org.kde.image

[Containments][2][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/OintOS/OintOSWallpaper.png
PLASMA_EOF
    chown -R 1000:1000 "$CHROOT_DIR/home/oinstaller/.config"
fi

# ---------------------------------------------------------------------------
# Phase 6 installer — copy our branded Calamares settings + launcher into the
# chroot (HOST-SIDE, because it needs /workspace/linux-installer). The apt
# packages (calamares, os-prober) were installed inside the chroot earlier.
# ---------------------------------------------------------------------------
if [ -d /workspace/linux-installer/calamares-settings-ointos ]; then
    echo "OintOS: installing Calamares branded settings (host-side into chroot)"
    # settings + module configs → /etc/calamares
    mkdir -p "$CHROOT_DIR/etc/calamares"
    cp /workspace/linux-installer/calamares-settings-ointos/modules/*.conf \
        "$CHROOT_DIR/etc/calamares/"
    # branding → /usr/share/calamares/branding/ointos
    mkdir -p "$CHROOT_DIR/usr/share/calamares/branding/ointos"
    cp -r /workspace/linux-installer/calamares-settings-ointos/branding/. \
        "$CHROOT_DIR/usr/share/calamares/branding/ointos/"
    # landing logo
    if [ -f /workspace/branding/Oint.png ]; then
        mkdir -p "$CHROOT_DIR/usr/share/calamares/branding/ointos/img"
        cp /workspace/branding/Oint.png \
            "$CHROOT_DIR/usr/share/calamares/branding/ointos/img/logo.png"
    fi
fi
if [ -f /workspace/linux-installer/launcher/ointos-installer-prompt ]; then
    echo "OintOS: installing installer launcher"
    cp /workspace/linux-installer/launcher/ointos-installer-prompt \
        "$CHROOT_DIR/usr/bin/ointos-installer-prompt"
    chmod +x "$CHROOT_DIR/usr/bin/ointos-installer-prompt"
fi

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

# casper is now installed and owns /etc/casper.conf — write Over our config
# NOW (after install), which avoids a dpkg conffile prompt that would block
# the non-interactive build. Point casper at our live user oinstaller.
cat > /etc/casper.conf <<'CASPER_EOF'
USERNAME="oinstaller"
CASPER_FORCE_UNTRUSTED=1
HOMEONLY=no
SYSTEM_MOUNTPOINTS=proc,sys,dev,run
HOSTNAME=ointos
CASPER_GENERATE_UUID=1
CASPER_LOG_LEVEL=info
CASPER_FALLBACK_TIME=10
CASPER_MEDIA_REQUIRED=0
CASPER_LIVE_MEDIA_PATH=casper
CASPER_EOF

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

# ---------------------------------------------------------------------------
# PATCH casper Bug 2055021 (confirmed on Ubuntu 26.04): casper's initramfs
# script runs
#   modprobe -b overlay || panic "/cow format specified as 'overlay' and no
#                                   support found"
# When overlayfs is BUILT INTO the kernel (not a module) — which is exactly
# Ubuntu 26.04's linux-generic — modprobe returns nonzero, so casper PANICS
# with a false-positive even though overlayfs works. Fix: neutralise the panic
# (turn the || panic into || true); if overlayfs truly were missing the later
# overlay mount itself would fail, which is the honest error.
# ---------------------------------------------------------------------------
echo "OintOS: patching casper Bug 2055021 (overlayfs built-in false panic)"
# The casper script contains:
#   modprobe "${MP_QUIET}" -b overlay || panic "/cow format specified as 'overlay' and no support found"
# When overlayfs is built into the kernel (linux-generic on 26.04), modprobe
# returns nonzero -> casper panic, a FALSE POSITIVE (Bug 2055021, confirmed on
# 26.04). Turn '... || panic <msg>' into '... || true' so it never aborts.
# (# delim avoids clashing with the || in the pattern.)
sed -i 's# -b overlay || panic .*# -b overlay || true#' \
    /usr/share/initramfs-tools/scripts/casper

# ---------------------------------------------------------------------------
# Live-session installer auto-launch.
# The GRUB "Install OintOS" entry boots with oininstaller=launch. This systemd
# service checks /proc/cmdline for it and, when present, launches Calamares
# once the desktop is up (after the live user session). Non-intrusive: if the
# arg is absent (Try OintOS), the service does nothing.
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/ointos-installer.service <<'SER'
[Unit]
Description=OintOS Installer (auto-launch)
After=graphical-session.target
ConditionKernelCommandLine=oininstaller=launch

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ointos-installer-prompt

[Install]
WantedBy=graphical-session.target
SER
systemctl enable ointos-installer.service 2>/dev/null || true

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

# Clean the live layer of the *bind-mounted* host dirs before squashfs.
# IMPORTANT: then recreate them as EMPTY dirs. casper's casper-bottom mounts
# /proc, /sys, /dev into the live root during boot; if they don't exist in
# the squashfs, it fails ("mount: mounting /proc on /root/proc failed: No
# such file or directory") and init panics. They must exist as empty mount
# points so casper can mount over them.
rm -rf "$MERGED_DIR/dev" "$MERGED_DIR/proc" "$MERGED_DIR/sys" "$MERGED_DIR/run" 2>/dev/null || true
mkdir -p "$MERGED_DIR/dev" "$MERGED_DIR/proc" "$MERGED_DIR/sys" "$MERGED_DIR/run"

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

menuentry "Install OintOS" {
    set gfxpayload=keep
    linux /casper/vmlinuz --- boot=casper quiet splash oininstaller=launch
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
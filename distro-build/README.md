# OintOS Distro Build

This directory contains the live-build configuration for building the OintOS ISO.

## Prerequisites

On the build machine (Ryzen 5 5500 desktop recommended), install:

```bash
sudo apt-get install -y \
    live-build debootstrap squashfs-tools xorriso \
    genisoimage grub-efi-amd64-bin grub-pc-bin \
    mtools dosfstools git
```

## Building the ISO

```bash
cd distro-build
sudo ./build.sh
```

The build takes 30-90 minutes depending on hardware and network speed.

Output files are in `output/`:
- `OintOS-1.0-amd64-YYYYMMDD.iso` — The bootable ISO
- `OintOS-1.0-amd64-YYYYMMDD.iso.sha256` — SHA-256 checksum
- `build-YYYYMMDD.log` — Build log

## Testing the ISO

### QEMU/KVM (recommended)
```bash
qemu-system-x86_64 -cdrom output/OintOS-1.0-amd64-*.iso \
    -m 4096 -enable-kvm -smp 2
```

### VirtualBox
1. Create a new VM (Type: Linux, Version: Ubuntu 64-bit)
2. Set RAM to 4096 MB
3. Mount the ISO in the optical drive
4. Boot the VM

### Test checklist
- [ ] ISO boots to live environment
- [ ] KDE Plasma desktop loads
- [ ] SDDM login screen appears
- [ ] NetworkManager detects network
- [ ] Dolphin file manager works
- [ ] Konsole terminal works
- [ ] Brave Browser launches
- [ ] System settings accessible

## Package Lists

Package lists are in `config/package-lists/`:
- `base.list.chroot` — Core Ubuntu base system
- `kde-desktop.list.chroot` — KDE Plasma desktop
- `gaming.list.chroot` — Steam, Wine (placeholder — Phase 9)
- `btrfs-tools.list.chroot` — Btrfs utilities
- `system-tools.list.chroot` — System utilities

## Build Hooks

Hooks in `config/hooks/live/` run during the build:
- `0000-add-brave-repo.chroot` — Installs Brave Browser
- `0100-enable-i386.chroot` — Enables i386 for gaming
- `0200-kde-defaults.chroot` — Configures KDE defaults
- `0300-remove-telemetry.chroot` — Removes telemetry
- `0400-system-tweaks.chroot` — System configuration

## Current Status

This is a **prototype** ISO — a live environment only, no installer yet.
The installer will be added in Phase 6 (Linux-side) and Phase 7 (Windows-side).

# Build Pipeline Decision: Abandon live-build → manual casper (livecd-rootfs style)

**Date:** 2026-08-29
**Status:** Decision record
**Supersedes:** `003-build-tool-choice.md` (live-build) — replaced in favor of a manual casper pipeline
**Phase:** 3 — Ubuntu 26.04 + KDE Plasma prototype

## Problem

Our live-build pipeline kept failing late in the binary stage on Ubuntu 26.04's *broken* live-build packaging — all bootloader paths are broken:
- `--bootloader grub` → tries to install `grub-legacy` (removed) → `E: Package 'grub-legacy' has no installation candidate` (Ubuntu Bug 2154055)
- default `syslinux` → tries `syslinux-themes-ubuntu-oneiric` (from Ubuntu **11.10!**) → also broken

Every fix was a guess costing 15–85 min builds; the upstream bugs have no clean config fix. Additionally, `--keep-cache` resume repeatedly failed with dpkg `start-stop-daemon` corruption from partial chroots.

## Finding: a proven working recipe exists

The reporter of Bug 2154055 (Proman4713, project "Utile OS" — GitHub Actions build badge **passes** on Ubuntu 26.04) does **not use live-build at all**. Their `tooling/isobuild.sh` builds the ISO **manually**, modeled on Ubuntu's own `livecd-rootfs`:

1. `debootstrap resolute` → chroot
2. `setup_chroot` (bind-mount /dev /proc /sys /run, resolv.conf)
3. Install packages/snaps, overlay live layer
4. Install `casper` + `initramfs-tools`; generate initramfs (`CASPER_GENERATE_UUID`, `LAYERFS_PATH`)
5. Copy `vmlinuz`/`initrd` → `ISO/casper/`
6. `mksquashfs` → `casper/filesystem.squashfs` + `filesystem.live.squashfs`
7. Casper metadata: `filesystem.size`, `filesystem.manifest*`, `install-sources.yaml`, `.disk/casper-uuid-generic`
8. **Manual GRUB**: write own `boot/grub/grub.cfg`; copy official modules (`x86_64-efi`, `i386-pc`), fonts, `EFI/boot/{bootx64.efi,grubx64.efi,mmx64.efi}` from `shim-signed`/`grub-efi-amd64-*`
9. EFI image (`mkfs.msdos` + `mcopy`)
10. **xorriso hybrid assembly** (`--grub2-mbr boot_hybrid.img`, eltorito BIOS + `-append_partition 2 0xef efi.img` GPT/EFI)

This **completely bypasses** live-build's broken `lb_binary_grub`.

## Decision

**Replace the live-build pipeline with a manual `debootstrap + casper + custom GRUB` pipeline (the Utile-OS `isobuild.sh` approach), adapted for OintOS: KDE Plasma instead of GNOME, our package set, no snaps for now.**

### Rationale
1. **Proven**: Utile-OS's GitHub Actions badge passes on Ubuntu 26.04 — this exact approach works.
2. **Bypasses broken upstream live-build**: no more `grub-legacy`/`syslinux-themes` fight.
3. **Right architecture for OintOS's roadmap**: casper live layout + full manual GRUB control is exactly what we need for the later Libertix-based Windows installer (dual-boot, Btrfs, custom boot entries, recovery).
4. **Transparency/audit**: a single deterministic shell script matches the master prompt's "build process must be auditable" requirement better than a patched-together live-build config.
5. **No snaps in v1**: OintOS is APT-first; drop Utile's snap seeding for our prototype.

### Trade-offs
- More code to maintain (debootstrap→casper→xorriso by hand) vs. live-build's automation.
- Need to replicate initramfs-casper details correctly (the `casperize.conf`/`default-layer.conf`/`update-initramfs` incantations) — but the recipe is proven and captured.
- Kernel install: rely on `linux-generic-hwe-26.04` (or `linux-generic`) in the chroot via apt, then copy `vmlinuz`/`initrd`.

## Scope of this change

New `distro-build/isobuild.sh` (the manual pipeline) + `distro-build/setup.sh`/list support. The live-build `config/` tree is retired (kept in git history). The package lists are adapted (we already fixed: `kde-spectacle`, no `oxygen5`, no `wireless-tools`, no gaming for Phase 9, no memtest).

**Verification:** the resulting ISO boots in a VM to a casper live session and shows the KDE Plasma desktop.
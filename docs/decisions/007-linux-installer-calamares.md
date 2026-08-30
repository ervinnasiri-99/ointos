# Linux Installer Framework: Calamares

**Status:** Decision (2026-08-30)
**Phase:** 6 — Linux-side live installer
**Supersedes:** the open item "live installer framework TBD"

## Decision

Use **Calamares** as OintOS's Linux-side installer framework, packaged and
branded the way Kubuntu 26.04 does today:
- deb packages: `calamares` + our own `calamares-settings-ointos`
- launched from the live KDE session via a `kubuntu-installer-prompt`-style
  launcher
- configured to unpack `/cdrom/casper/filesystem.squashfs` (our casper live
  layout) with the distro-configurable `btrfsSubvolumes` layout
  (`@`, `@home`, `@cache`, `@log`, `@swap`)

## Why Calamares (against OintOS's four hard requirements)

1. **Works on our exact stack today.** Kubuntu 26.04 (Ubuntu 26.04 + Plasma +
   casper) ships `calamares 3.3.14-0ubuntu25` + `calamares-settings-kubuntu
   1:26.04.12` + `kubuntu-installer-prompt 26.04.2`. Kubuntu Focus runs a
   production Timeshift-style Btrfs rollback on Calamares. We are adopting the
   same config a shipping current-LTS Ubuntu+Plasma distro uses, not adopting a
   framework in a vacuum.
2. **Btrfs `@`/`@home` + Timeshift is native.** The `mount` module's
   `btrfsSubvolumes:` produces the Ubuntu-type subvolume layout Timeshift
   mandates (`@` + `@home`, etc.). This is exactly the deferred-Phase-5
   dependency.
3. **Live-from-casper install is Calamares's canonical mode on Ubuntu flavors:**
   `unpackfs` reads `/cdrom/casper/filesystem.squashfs`. We keep our custom
   GRUB + casper layout with no restructuring.
4. **KDE-native, GPL-3.0-compatible, highly brandable** (`branding.desc`,
   QML slideshow, Qt stylesheet). A Plasma product ships a Plasma-native
   installer.

## Accepted tradeoffs (built around)

- **No native autoinstall spec.** We build a thin YAML→config plan driver
  (`linux-installer/unattended/plan.py`) that pre-seeds `/etc/calamares`
  configs from an install plan and invokes Calamares headlessly. Schema is
  shaped subiquity-style so the Windows/Libertix side speaks one format.
- **Secure Boot needs our own Microsoft-signed shim** (Calamares `sb-shim`
  bootloader option). Non-SB UEFI + BIOS work today; budget the signing
  workflow separately.

## Rejected options

- **Ubuntu Desktop Installer / subiquity:** deliberately ships *flat* Btrfs
  with **no `@`/`@home` subvolumes**, cannot create subvolumes in manual
  partitioning — forces a subiquity fork for Phase 5. UI is Flutter/Yaru,
  GNOME-oriented (wrong for a KDE product). Ships as a snap (adds snapd
  dependency to our snap-free build). Its strengths (best autoinstall, TPM-FDE,
  Secure Boot) don't outweigh these.
- **Ubiquity:** dead upstream (>23.10), no unattended mode, GTK/legacy.
- **Custom / Mint-style live-installer:** GTK, not yet Mint's own default,
  unattended is WIP; re-implementing partition+bootloader hardening from
  scratch is the highest long-term cost.

## Sources
- Calamares Deployer's Guide: https://calamares.codeberg.page/docs/deploy-guide/
- Calamares `mount.conf` btrfsSubvolumes / `bootloader.conf` sb-shim:
  https://github.com/calamares/calamares/tree/master/src/modules
- Generalized btrfs subvolumes PR #1622, hybrid BIOS+UEFI PR #2422 (calamares)
- Shipped Kubuntu 26.04 manifest (calamares + settings + prompt packages):
  https://kubuntu.org/news/kubuntu-26-04-release-notes/
- Kubuntu casper `unpackfs` wiring: https://bugs.launchpad.net/ubuntu/+source/calamares/+bug/2100956
- kubunt-installer-prompt Wayland/sudo-rs launch fix: https://bugs.launchpad.net/bugs/2124199
- Ubuntu 26.04 Btrfs flat-layout / no subvolumes:
  https://askubuntu.com/questions/1566142/ubuntu-26-04-btrfs-missing-subvolumes
- Timeshift supported configs (requires `@`/`@home`):
  https://github.com/linuxmint/timeshift

## Licensing
Calamares is GPL-3.0 — compatible with the OintOS project (GPL-3.0 + Libertix
fork). Our `calamares-settings-ointos` + plan driver are likewise GPL-3.0.
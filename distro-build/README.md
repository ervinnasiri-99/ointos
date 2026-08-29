# OintOS Distro Build

Builds the OintOS ISO (Ubuntu 26.04 LTS + KDE Plasma) as a bootable **casper
live ISO** — using a **manual `debootstrap` + casper + custom-GRUB pipeline**,
NOT live-build.

> **Why not live-build?** Ubuntu 26.04's live-build is broken for custom ISOs
> (Ubuntu Bug 2154055): `--bootloader grub` wants the removed `grub-legacy`
> package, and even the default `syslinux` wants packages from Ubuntu 11.10.
> We build by hand, modeled on Ubuntu's own `livecd-rootfs` and the proven
> recipe in [Utile-OS](https://github.com/Proman4713/Utile-OS) (which has a
> passing Ubuntu 26.04 ISO build on GitHub Actions). See
> `docs/decisions/004-build-pipeline-casper.md`.

---

## One-time build-machine setup

On your WSL2 Ubuntu (or any root-capable Ubuntu 26.04 — e.g. a
`docker run -it ubuntu:26.04` container):

```bash
cd ~
git clone https://github.com/ervinnasiri-99/ointos.git
cd ointos/distro-build
./setup-wsl.sh           # installs the build tools
```

## Build the ISO

```bash
sudo bash isobuild.sh
```

Takes roughly **30–90 minutes** (debootstrap + apt install of KDE + squashfs).
Needs **~25 GB free** and **~8 GB RAM**.

Output in `distro-build/output/`:
- `OintOS-1.0-amd64.iso` — the bootable hybrid (BIOS+EFI) casper live ISO
- `OintOS-1.0-amd64.iso.sha256`

### Env vars
- `OINTOS_VERSION=1.0` — image version
- `OINTOS_WORK_DIR=/opt/ointos-build` — build scratch dir (def: `/opt/ointos-build`)

---

## Test the ISO in a VM

```bash
qemu-system-x86_64 -cdrom output/OintOS-1.0-amd64.iso -m 4096 -enable-kvm -smp 2
```

Test checklist:
- [ ] ISO boots to casper live session
- [ ] GRUB menu shows "Try OintOS"
- [ ] KDE Plasma desktop loads
- [ ] SDDM / console login works (`oinstaller` / password `ointos`)
- [ ] Network works
- [ ] Dolphin, Konsole, Brave launch
- [ ] Btrfs tools present

---

## How it works (`isobuild.sh`)

1. **debootstrap** `resolute` base → chroot
2. Install **KDE Plasma + OintOS packages** into chroot (`linux-generic` kernel, casper, btrfs-progs, timeshift, etc.), set `os-release` = OintOS, **disable telemetry** (apport/whoopsie), create `oinstaller` user
3. Create an **overlay live layer**, install `casper`, regenerate initramfs with casper layer support
4. Copy `vmlinuz`/`initrd` → `ISO/casper/`, `mksquashfs` → `filesystem.squashfs`
5. Casper metadata (`filesystem.size`, `install-sources.yaml`, `.disk/`)
6. **Manual GRUB**: write `boot/grub/grub.cfg`, copy official modules (`x86_64-efi`, `i386-pc`), fonts, `EFI/boot/{bootx64.efi,grubx64.efi,mmx64.efi}` (shim + signed grub)
7. Build EFI partition image; `xorriso` → **hybrid ISO** (BIOS grub-mbr + EFI appended partition)

## ⚠️ CRITICAL: casper-uuid-generic (boot-failure gotcha)

casper's initramfs will **reject a perfectly good live medium** with *"Unable
to find a medium containing a live file system"* if the ISO root `.disk/`
has no `casper-uuid-*` file matching the initrd's generated UUID.

- casper generates a UUID into the initrd (`conf/uuid.conf`, via
  `CASPER_GENERATE_UUID`).
- `check_dev()` mounts the ISO, finds `/casper/*.squashfs` (passes), then
  `matches_uuid()` requires `.disk/casper-uuid-*` to contain the matching UUID.
- Without it → the medium is rejected → the boot prompt above.

`isobuild.sh` handles this by extracting the UUID from the initrd
(`unmkinitramfs` → `conf/uuid.conf`) and writing
`$ISODIR/.disk/casper-uuid-generic`. **Do not remove that step.**

(Symptom was diagnosed via a QEMU `break=premount` initramfs `sh -x` trace:
`find_livefs` → `is_casper_path` returned 0, then the UUID gate rejected the
device. `install-sources.yaml` is NOT what casper uses to find the medium.)

---

## Current Status / Roadmap

- Phase 3: prototype **live** ISO (KDE + casper, no installer yet) — this script.
- Gaming stack (Steam/Proton/Wine), installer, Btrfs *installed* system, OOBE →
  later phases (see `docs/master-prompt.md`). The live ISO already includes
  `btrfs-progs` + `timeshift` for the live environment.
- Branding is placeholder (`OintOS 1.0`); Phase 14 handles real branding.
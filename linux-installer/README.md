# OintOS Linux-Side Live Installer

Phase 6 deliverable: the installer that runs from the OintOS live KDE session
and installs the OintOS system to a target disk, plus the unattended plan
driver used by the Windows-side handoff.

## Framework: Calamares

Decision + rationale in `docs/decisions/007-linux-installer-calamares.md`.
Short version: Calamares (Kubuntu 26.04 ships it on the same Ubuntu+Plasma+
casper stack), because its Btrfs subvolume module produces the `@`/`@home`
layout Timeshift mandates (Phase 5), it installs from our casper live layout
(`unpackfs` reads `/cdrom/casper/filesystem.squashfs`), is KDE-native and
GPL-3.0.

## Layout

```
linux-installer/
├── calamares-settings-ointos/    # branded config + branding (installed into the ISO)
│   ├── branding/                 # branding.desc, show.qml slideshow, stylesheet.qss
│   ├── modules/                  # partition/mount/unpackfs/users/bootloader/shellprocess/displaymanager/settings.conf
│   └── install.sh                # copies configs + branding into the live image
├── launcher/
│   └── ointos-installer-prompt   # launches Calamares from the live KDE session (Wayland-safe)
└── unattended/
    ├── plan.py                   # read YAML/JSON install plan -> /etc/calamares configs + headless run
    └── example-plan.yaml         # example plan (subiquity-shaped)
```

## Interactive install (from the live desktop)

- Boot the OintOS ISO; GRUB → **"Install OintOS"** (or pick "Try OintOS" and
  run `ointos-installer-prompt` in a terminal).
- The installer launches Branded Calamares: locale → keyboard → partition →
  user → summary. It unpacks `/cdrom/casper/filesystem.squashfs` onto a Btrfs
  `@`/`@home`/... layout and installs GRUB (os-prober for dual-boot).

## Unattended install (Windows-side handoff)

Used by the Libertix Windows handoff (Phase 7). `plan.py` turns an install
plan into Calamares configs and runs headlessly:

```bash
sudo python3 unattended/plan.py unattended/example-plan.yaml
```

- Plan is YAML/JSON, subiquity-shaped (`identity`, `storage`, `late_commands`).
- `--dry-run` writes configs without installing; `--cal-conf` overrides
  `/etc/calamares`.
- Writes an exec-only `settings.conf` (partition → mount → unpackfs → users →
  displaymanager → bootloader → shellprocess → finished) so there's no UI.
- `shellprocess.conf` carries the plan's `late_commands`.

## Integration with the ISO build

`distro-build/isobuild.sh`:
- installs `calamares` + `os-prober` + `python3-yaml` in the chroot,
- copies `calamares-settings-ointos` configs + branding + launcher host-side
  into the image,
- adds a GRUB `Install OintOS` entry (kernel arg `oininstaller=launch`),
- adds a systemd service that auto-launches the installer when that arg is set.

## Phase 5 tie-in

The Btrfs layout this installer creates (`@`, `@home`, ...) is what deferred
Phase 5 (snapshot/rollback) needs — once the installer produces it, Phase 5
lands on a real installed system.

## Testing

`distro-build/otest4.sh` verifies the installed system after a test install
(subvolumes, GRUB, users, timeshift config, no snapd).
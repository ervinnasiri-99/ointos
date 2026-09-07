# OintOS Linux-Side Live Installer

Phase 6 deliverable: the installer that runs from the OintOS live KDE session
and installs the OintOS system to a target disk, plus the unattended plan
driver used by the Windows-side handoff.

## Framework: Calamares

Decision + rationale in `docs/decisions/007-linux-installer-calamares.md`;
filesystem reversal in `008-ext4-default-drop-btrfs.md`.
Short version: Calamares (Kubuntu 26.04 ships it on the same Ubuntu+Plasma+
casper stack), because it installs from our casper live layout (`unpackfs`
reads `/cdrom/casper/filesystem.squashfs`), is KDE-native and GPL-3.0.
Target filesystem is ext4 (Btrfs dropped after the build15 unpackfs RAM
freeze — see 008).

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
  user → summary. It unpacks `/cdrom/casper/filesystem.squashfs` onto an
  ext4 root and installs GRUB (os-prober for dual-boot).

## Unattended install (Windows-side handoff)

Used by the Libertix Windows handoff (Phase 7). `plan.py` turns an install
plan into Calamares configs and runs headlessly:

```bash
sudo python3 unattended/plan.py unattended/example-plan.yaml
```

- Plan is YAML/JSON, subiquity-shaped (`identity`, `storage`, `late_commands`).
- `--dry-run` writes configs without installing; `--cal-conf` overrides
  `/etc/calamares`.
- Writes an exec-only `settings.conf` (same exec chain as the interactive
  one, Kubuntu-trimmed) so there's no UI.
- `shellprocess.conf` carries the plan's `late_commands`.

## Integration with the ISO build

`distro-build/isobuild.sh`:
- installs `calamares` + `os-prober` + `python3-yaml` in the chroot,
- copies `calamares-settings-ointos` configs + branding + launcher host-side
  into the image,
- adds a GRUB `Install OintOS` entry (kernel arg `oininstaller=launch`),
- adds a systemd service that auto-launches the installer when that arg is set.

## Phase 5 tie-in (dropped per 008)

Btrfs snapshot/rollback was deferred to Phase 5, then dropped entirely
(ext4 default after the build15 unpackfs RAM freeze).

## Testing

`distro-build/otest4.sh` verifies the installed system after a test install
(ext4 root, GRUB, users, no snapd, no btrfs leftovers).
## Calamares 3.3.x gotchas (from debugging)

### `modules-search: [ local ]` is mandatory
Without it the search list is **empty**, zero modules are found, and EVERY
module fails with "not found in module search paths" → the "unable to load
all of the configured modules" dialog. `local` = `$LIBDIR/calamares/modules`
(`/usr/lib/x86_64-linux-gnu/calamares/modules`). Verified in
`src/libcalamares/Settings.cpp` (`interpretModulesSearch`): missing key =
empty list, no builtin default.

### Module `.conf` files live in `modules/`, not next to `settings.conf`
Calamares only searches `/etc/calamares/modules` + `/usr/share/calamares/
modules` for `<module>.conf`. A conf placed directly in `/etc/calamares/`
is silently ignored (module still loads — missing conf is warning-only,
fatal only on YAML syntax errors; see `Module::loadConfigurationFile`).
`isobuild.sh`/`install.sh` put `settings.conf` in `/etc/calamares/` and
everything else in `/etc/calamares/modules/`.

### No `--is-installer` flag
Calamares 3.3.x has **no** `--is-installer` CLI flag. Installer mode is determined
entirely by `settings.conf` (the `sequence` with `exec` modules). The correct
invocation is just `calamares` (or `calamares -c /etc/calamares`).

### Required settings.conf booleans
Calamares 3.3.x **will complain** if these are not explicitly set:
```yaml
prompt-install: false
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false
quit-at-end: false
```

### App menu "Install System"
The `calamares` package ships a `.desktop` file that launches Calamares with the
default config. When clicking "Install System" in the KDE app menu, Calamares
reads `/etc/calamares/settings.conf` (our installed config) and shows the
installer if the sequence has `exec` modules. No `--is-installer` needed.

### Launching from terminal (for debugging)
```bash
sudo calamares -c /etc/calamares -d 2>&1 | tee /tmp/calamares-debug.log
```

# OintOS Distro Build

This directory contains the live-build configuration for building the OintOS ISO
(Ubuntu 26.04 LTS + KDE Plasma).

## Two build scripts

- **`build.py`** (recommended) — Python build script with full verbose logging
  to both console and a timestamped log file. Streaming subprocess output,
  disk/RAM checks, ISO verification, and automatic SHA-256 generation.
- **`build.sh`** — simple Bash wrapper (simpler, less logging).
- **`setup-wsl.sh`** — one-time setup helper for WSL2 Ubuntu (installs
  prerequisites, verifies tools, guides `.wslconfig` memory bump).

---

## Building inside WSL2 Ubuntu (recommended)

This is the fastest path on the Windows/Ryzen machine.

### 1. One-time WSL2 setup

```bash
cd ~
git clone https://github.com/ervinnasiri-99/ointos.git
cd ointos/distro-build
./setup-wsl.sh
```

The setup script installs live-build + all prerequisites and helps you configure
WSL2 memory via `.wslconfig` (recommend `memory=8GB`).

> **Important:** keep the repo inside the WSL2 filesystem (`~/ointos`), **not**
> on `/mnt/c/...` — builds on the Windows drive are far slower.

### 2. Build the ISO

```bash
cd ~/ointos/distro-build
sudo python3 build.py
```

- Takes **30–90 minutes** depending on hardware/network.
- Needs **~25 GB free disk** and **~8 GB RAM** peak.
- Writes a **full verbose log** to `output/build-<timestamp>.log` that mirrors
  everything to the console.
- Produces `output/OintOS-1.0-amd64-<date>.iso` + `.sha256`.

### 3. Test the ISO in a VM

```bash
qemu-system-x86_64 -cdrom output/OintOS-1.0-amd64-*.iso \
    -m 4096 -enable-kvm -smp 2
```

---

## Building on native Ubuntu (bare metal)

```bash
cd distro-build
sudo ./build.sh          # or: sudo python3 build.py
```

Requires the same prerequisites; `build.py` installs them automatically unless
you pass `--no-prereqs`.

---

## Build disk/RAM requirements

| Resource | Required | Recommended |
|----------|----------|-------------|
| Disk space | 25 GB free | 30 GB+ |
| RAM | 4 GB | 8 GB |
| Build time | — | 30–90 min |

---

## Output

Output files are in `distro-build/output/`:
- `OintOS-1.0-amd64-YYYYMMDD.iso` — The bootable ISO
- `OintOS-1.0-amd64-YYYYMMDD.iso.sha256` — SHA-256 checksum
- `build-YYYYMMDD-HHMMSS.log` — Full verbose build log

---

## Test checklist (in the VM)

- [ ] ISO boots to live environment
- [ ] KDE Plasma desktop loads
- [ ] SDDM login screen appears
- [ ] NetworkManager detects network
- [ ] Dolphin file manager works
- [ ] Konsole terminal works
- [ ] Brave Browser launches
- [ ] System settings accessible

---

## Package Lists

Package lists are in `config/package-lists/`:
- `base.list.chroot` — Core Ubuntu base system
- `kde-desktop.list.chroot` — KDE Plasma desktop (curated)
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

---

## Current Status

This is a **prototype** ISO — a live environment only, no installer yet.
The installer will be added in Phase 6 (Linux-side) and Phase 7 (Windows-side).

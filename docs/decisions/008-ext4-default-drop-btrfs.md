# 008 — ext4 default, Btrfs dropped

**Status:** Decision 2026-09-07 (user-confirmed)
**Supersedes:** `006-phase5-deferred.md`, Btrfs sections of `007-linux-installer-calamares.md`.

## Why

build15 ISO (Calamares 3.3.14, Btrfs `@`/`@home`/`@cache`/`@log` + `@swap`,
swapfile=`file`): the 8GB live VM froze ~13% into unpackfs
(26580/193887 files), rsync died code 11. Live session showed 4.1Gi
`shared` (= tmpfs-resident writes) + 6.3Gi buff/cache against a 5.57GB
unpacked / 2.2GB-xz payload. Kubuntu (same Calamares, ext4) installs fine
on 4GB RAM.

Three parallel audits (repo sweep, web research incl. CachyOS mount code +
upstream `main.py`, live-RAM measurement) established:
- Repo sets zero live tmpfs sizing (`/cow` defaults to 50% RAM ≈ 4GB <
  5.57GB payload → ENOSPC if writes land on cow). No `toram` (good).
- Prime suspect, unproven without a freeze-proof log: mount job silently
  failed → rsync dest `/tmp/calamares-root-*` sits on `/cow` tmpfs.
- Ruled out: disk-full, toram, libkpmcore bug, missing rsync `-S`
  (in `-aHAXSr` since 2023), `compress=zstd:1`, missing fstab module.

User decision: default to ext4; if the ext4 install goes green, Btrfs is
gone for good — including the Timeshift/`@` snapshot story (Phase 5).

## What changed (Layer 0)

- `partition.conf`: `defaultFileSystemType: ext4`,
  `availableFileSystemTypes: [ext4]`, swap choices `[none, file]`
  (Kubuntu resolute verbatim), default `file`. small/suspend create a
  real swap partition; file = swapfile later, no partition.
- `mount.conf`: deleted `btrfsSubvolumes`, `btrfsSwapSubvol`, btrfs/btrfs_swap
  `mountOptions`. Plain mounts only.
- `shellprocess.conf`: dropped timeshift `mkdir` hook.
- `isobuild.sh`: removed `btrfs-progs` + `timeshift` (PACKAGES_SYSTEM +
  chroot install blocks); `linux-headers-generic` already dropped earlier.
- `plan.py` + `example-plan.yaml`: ext4, no `subvolumes` key, no `_subvol`.
- `otest3.sh`/`otest4.sh` (+`otest.sh`, `otest2.sh`): assert ABSENCE of
  btrfs/timeshift; `otest4.sh` §A asserts ext4 root + fails on `@` dirs /
  `subvol=` in fstab.
- `welcome.conf`: `requiredStorage: 12`, `requiredRam: 4` (honest floor for
  the 5.57GB payload; kept).

## Consequences

- Phase 5 (snapshot/rollback) is CANCELLED, not deferred. `master-prompt.md`
  Btrfs/Timeshift requirements are annotated, not yet rewritten.
- `btrfs-progs` is not even in the live ISO: no manual Btrfs tinkering
  from the live session either. Revisit only with a freeze-proof log
  proving the mount chain.
- Layer 1 (watchdog VDI evidence) ships with the same build; Layer 2
  (zstd squashfs, cow sizing, payload diet) only if ext4 still freezes.

# Phase 5 — Deferred until installer (Phase 6) exists

**Status:** Decision 2026-08-30 (user-confirmed)
**Phase 5 (master prompt):** Btrfs + snapshot/rollback integration.

## Why it's deferred
Installed-system Btrfs fundamentally requires a **Linux-side installer** to
create the filesystem at install time. The live ISO is fun to boot but does
not *install* a persistent system, so:
- The **subvolume layout** (`@`, `@home`, `@snapshots`, …) is set up by the
  installer, not by the live environment.
- **Snapshot/rollback** (Timeshift-style) applies to an *installed* root, not
  the squashfs live session.
- Baking Btrfs install logic now would be guessing the installer's
  architecture before it exists (Phase 6 is still an open decision).

## What's already in place (kept, useful later)
- `btrfs-progs` + `timeshift` **installed in the live ISO** (present in
  `isobuild.sh`). The live session has the tools.
- The live squashfs itself is not Btrfs (it's squashfs — that's correct for a
  live medium).

## Phase 5 work to do AFTER Phase 6 (when the installer exists)
1. Define the install-time Btrfs **subvolume layout** (e.g. `/` → `@`,
   `/home` → `@home`, `/var/@snapshots`).
2. Configure **Timeshift** for the installed system (rsync vs Btrfs mode,
   snapshot schedule, exclude lists).
3. Wire the **installer** (Phase 6) to create that layout + a baseline
   snapshot at first boot.
4. Add snapshot/rollback **restore path** + docs.
5. Test install→snapshot→rollback in VMs.

## Prerequisite for Phase 5
Phase 6 (Linux-side live installer, framework decision + implementation)
must land first, because it defines where/when the Btrfs filesystem is
created.
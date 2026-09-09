# 009 — Phase 7 handoff: schema-v3 plan driver

**Status:** Implemented (commits 019–022), VM validation pending
**Phase:** 7 — Windows-side installer (Linux-side handoff layer)

## What

`linux-installer/unattended/plan.py` reads Libertix `installation-plan.json`
schema-v3 directly (auto-detected; legacy shorthand still works) and emits
Calamares configs for a headless install. Ships in the live ISO at
`/usr/local/bin/ointos-unattended-plan` (+ both example plans under
`/usr/share/doc/ointos/`).

## Mapping (verified against ekimiateam/libertix `main`)

| schema-v3 field | Target | Notes |
|---|---|---|
| `account.username` | `users.conf` presets.loginName | top-level `autologinUser` does NOT exist upstream (Config.cpp) |
| `account.computerName` | `/etc/hostname` late command | |
| `account.passwordHashWindowsPath` | `chpasswd -e` late command | `$6$` validated live-side, same rules as `libertix-install-main.sh` |
| `locale.*` | `locale.conf` region/zone + `/etc/default/locale`, `/etc/default/keyboard`, `/etc/localtime` late commands | `locale.conf` takes ONLY region/zone (schema `additionalProperties:false`); keyboard layout via files, not `keyboard.conf` |
| `disk.partitionStyle` + `firmware` | consistency check only | Calamares owns partitioning; plan never resizes |
| `distribution.osReleaseId` | must be `ubuntu` or `ointos` | live image writes `ID=ointos` (+`ID_LIKE="ubuntu debian"`, Mint precedent — apport needs `debian` or every traceback dies in its excepthook) |
| `runtime.secureBootEnabled=true` | refused | no signed shim (decision 007 limitation) |
| encrypted BitLocker state | refused | decrypt/suspend first |
| staging discovery | `LABEL=OINTOSSTG` (vfat) → `/cdrom` → live-medium fallbacks | same pattern as `libertix-live-context.sh` |
| plan/state `planId` | must match when sibling state file present | same as live-context |

## Fail-closed list

Bad schemaVersion, GPT/BIOS or MBR/UEFI mismatch, SecureBoot=true,
encrypted BitLocker, reserved username (`root`, `oinstaller`), missing/bad
hash, plan/state `planId` mismatch, missing staging plan — all exit 2, never
silent.

## Interactive parity

`shellprocess.conf` (interactive) and `plan.py` late list are sync-checked:
identical modulo plan-specific bits (hostname/locale/pw/marker). Both write
`/etc/ointos-installed` (`otest4 §G` FAILs without it). Live-only tools
(`ointos-unattended-plan`, example plans, installer prompt) are purged from
the target (`otest4 §G` FAILs on leak).

## Out of scope (later Phase 7)

Windows `.exe` fork itself (`windows-installer/` still empty), FAT staging
creation on the Windows side, headless VM test of the full handoff.

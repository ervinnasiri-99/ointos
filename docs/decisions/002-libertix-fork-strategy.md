# Libertix Fork Strategy

**Date:** 2026-08-28
**Status:** Decision record
**Related:** [Libertix Architecture Assessment](../architecture/001-libertix-assessment.md)

---

## Fork Approach

### Strategy: Direct Fork with Clean Separation

OintOS will fork the Libertix repository directly (not reimplement from scratch) and maintain a clear boundary between upstream code and OintOS-specific adaptations.

### Repository Layout

```
windows-installer/
├── upstream/                    # Minimally-modified Libertix core
│   ├── Installation/            # Plan, state machine, validation
│   ├── Scripts/                 # PowerShell modules
│   ├── schemas/                 # JSON contracts
│   └── ...                      # Other upstream directories
└── ointos/                      # OintOS-specific adaptations
    ├── catalog/                 # OintOS distribution catalog
    ├── branding/                # Logo, splash, GRUB theme
    ├── iso-build/               # OintOS ISO build configuration
    └── config/                  # OintOS-specific settings
```

### Separation Rules

**What goes in `upstream/`:**
- Core installation plan model and validation
- State machine and execution ledger
- Rollback engine (shared + firmware adapters)
- Artifact verification and trust mechanism
- Live environment runtime framework
- JSON schemas
- Testing infrastructure framework

**What goes in `ointos/`:**
- Distribution catalog entry for OintOS
- ISO build configuration (Ubuntu+KDE base)
- Branding assets (logo, splash screen, GRUB theme)
- OintOS-specific post-install verification rules
- First-boot OOBE wizard integration
- Gaming stack setup scripts
- Btrfs configuration scripts

### Why This Separation?

1. **Upstream syncing** — When Libertix releases updates, we can diff against `upstream/` to see what changed
2. **Legal clarity** — GPL-3.0 obligations apply clearly to `upstream/`; `ointos/` code can be assessed separately
3. **Maintenance** — Bug fixes to core infrastructure go to `upstream/`; distro-specific changes go to `ointos/`
4. **Rebasing** — If we need to rebase on a newer Libertix version, the separation makes it tractable

---

## What Gets Modified in the Fork

### Distribution Catalog

Libertix currently supports Linux Mint 22.3 Cinnamon and Zorin OS 18.1 Core. OintOS needs to add itself as a distribution option.

**File:** `Installation/DistributionCatalogLoader.cs` (9KB)

The catalog is fetched from GitHub Pages and contains distribution metadata. We need to:
1. Add OintOS to the distribution catalog
2. Point to OintOS ISO URLs
3. Include correct SHA-256 hashes
4. Update the signed catalog with OintOS entries

### ISO Build Process

Libertix builds separate BIOS and UEFI ISOs via Docker. OintOS needs to:
1. Build an Ubuntu 26.04 + KDE Plasma base ISO
2. Include the gaming stack (Steam, Proton, Wine, WinBoat)
3. Include Btrfs tooling
4. Include the OintOS live installer configuration

**Directory:** `iso-tools/` — Adapt build scripts for OintOS ISO contents

### GRUB Menu

The GRUB menu needs OintOS-specific entries:
1. "OintOS" as the primary Linux entry
2. "Windows Boot Manager" for dual-boot
3. "Advanced options" for kernel selection
4. "Shutdown" option

**Directory:** `grub/` — Update menu generation scripts

### Branding

Replace Libertix branding with OintOS branding:
1. Boot splash screen
2. GRUB theme
3. Live environment wallpaper
4. Installer window title/icons

**Directory:** `ointos/branding/` — Placeholder assets until Phase 14

---

## What Stays as Generic Libertix Core

These components should NOT be modified for OintOS-specific needs:

1. **Installation plan model** — The typed plan structure is generic
2. **State machine** — The 14-step ordered process is generic
3. **Plan validation** — The validation rules are generic
4. **Rollback engine** — Compensatable transactions are generic
5. **Firmware adapter pattern** — BIOS/UEFI separation is generic
6. **Artifact verification** — Trust mechanism is generic
7. **JSON schemas** — Contract definitions are generic
8. **Testing framework** — Test infrastructure is generic

**Why keep these generic?**
- They're well-tested and safety-critical
- Changes here affect all distributions Libertix supports
- Upstream improvements apply automatically
- Reduces maintenance burden

---

## Build Process

### Prerequisites

- .NET Framework 4.8 SDK (for C#/WPF build)
- PowerShell 7+ (for UEFI scripts)
- Python 3.x with uv (for live installer and tests)
- Docker (for ISO builds)
- Visual Studio 2022 Build Tools (for WPF)

### Build Steps

1. **Build Windows app:**
   ```bash
   dotnet build Libertix.sln
   ```

2. **Build ISOs:**
   ```bash
   cd iso-tools
   ./build-isos-docker.sh
   ```

3. **Run tests:**
   ```bash
   cd auto_tests
   uv run pytest
   ```

### OintOS-Specific Build

1. **Prepare OintOS distribution catalog** — Add OintOS entry with correct hashes
2. **Build OintOS ISO** — Use Docker build with OintOS package list
3. **Test installer flow** — Verify OintOS appears in distribution selection
4. **Test installation** — Verify OintOS installs correctly in VMs

---

## Testing Approach

### Adapt Libertix's Test Framework

Libertix has a comprehensive automated test service (`auto_tests/`) that uses:
- Python API tests
- SSH/VNC VM automation
- Visual regression checks

OintOS should:
1. Reuse the test framework structure
2. Add OintOS-specific test cases
3. Test Btrfs installation flow
4. Test gaming stack installation
5. Test OOBE wizard integration

### VM Test Matrix

| Configuration | BIOS | UEFI |
|--------------|------|------|
| Windows 10, single disk, no BitLocker | ✓ | ✓ |
| Windows 11, single disk, no BitLocker | ✓ | ✓ |
| Windows 10, single disk, BitLocker | ✓ | ✓ |
| Windows 11, single disk, BitLocker | ✓ | ✓ |
| Windows 10, dual disk | ✓ | ✓ |
| Windows 11, dual disk | ✓ | ✓ |
| Insufficient disk space | ✓ | ✓ |
| Risky layouts (RAID, dynamic) | ✓ | ✓ |
| Interrupted installation | ✓ | ✓ |

---

## Open Questions

1. **Upstream sync frequency** — How often should we pull from upstream Libertix? Every release? Monthly? Ad hoc?

2. **Contribution back** — Should OintOS contributions (Btrfs support, gaming stack) be contributed upstream to Libertix? This depends on whether the changes are generic or OintOS-specific.

3. **WPF build on Linux** — The Windows app uses WPF (.NET Framework 4.8), which requires Windows or Mono. Can we cross-compile from Linux, or do we need a Windows build machine?

4. **Test VM images** — Libertix uses specific test VMs. Do we need to create OintOS-specific VM images, or can we reuse Libertix's with OintOS ISOs?

5. **Catalog signing** — How should OintOS distribution catalogs be signed? Do we need our own signing key, or can we use Libertix's infrastructure?

---

## Decision Record

| Field | Value |
|-------|-------|
| Fork strategy | Direct fork with upstream/ointos/ separation |
| License | GPL-3.0 (matching Libertix) |
| Upstream sync | TBD — assess after initial fork |
| Build process | Adapt Libertix's Docker-based ISO build |
| Testing | Reuse Libertix's test framework, add OintOS cases |
| Legal review | Pending — keep separation clean for optionality |

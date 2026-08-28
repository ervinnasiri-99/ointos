# Libertix Architecture Assessment

**Date:** 2026-08-28
**Status:** Phase 2 deliverable
**Purpose:** Comprehensive analysis of the Libertix repository to inform the OintOS fork strategy.

---

## 1. Repository Structure Overview

Libertix is organized by execution environment and responsibility:

| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| `Installation/` | Typed installation plan, validation, state machine | `InstallationPlan.cs`, `InstallationStateMachine.cs`, `InstallationPlanValidator.cs` |
| `Pages/` | Windows WPF UI + BIOS/UEFI preparation logic | `ApplyChanges.Bios.cs`, `ApplyChanges.Uefi.cs`, `ChooseDistro.xaml`, `ResizeDisk.xaml` |
| `Scripts/` | PowerShell modules for UEFI workflows and recovery | `modules/` (shared), `uefi/` (UEFI-specific) |
| `assets/live/` | Python live installer, firmware adapters, shared runtime | `libertix-install-main.sh`, `libertix-bios-adapter.sh`, `libertix-uefi-adapter.sh` |
| `iso/` | BIOS-specific boot inputs and thin entry wrappers | Live environment boot configuration |
| `iso-uefi/` | UEFI-specific boot inputs and thin entry wrappers | UEFI boot configuration |
| `iso-tools/` | Docker-based ISO build tooling | `build-isos-docker.sh` |
| `grub/` | GRUB configuration scripts (Python) | Menu generation, boot entry management |
| `schemas/` | Versioned JSON contracts | `installation-plan.schema.json`, `installation-state.schema.json` |
| `auto_tests/` | Automated test service | Python API tests, SSH/VNC VM automation, visual checks |
| `docs/` | Architecture documentation | `ARCHITECTURE.md`, UEFI boot details, release workflow |

**Tech stack:**
- C# / WPF (.NET Framework 4.8) — Windows GUI application
- PowerShell — UEFI preparation workflows, recovery scripts
- Python — Live installer, test framework, ISO build tooling, GRUB config
- Bash/Shell — ISO build scripts, live environment entry points
- Docker — Reproducible ISO builds without sudo
- JSON schemas — Machine-readable contracts for plan and state

---

## 2. Installation Plan & State Machine

### Installation Plan

Libertix uses a **typed, versioned installation plan** (schema v3) that serves as the single source of truth across all execution environments. The plan is atomically published before any disk mutation occurs.

**Plan contents:**
- Disk identity and geometry (disk path, partition layout, sizes)
- Distribution metadata (ISO path, SHA-256 hashes, version)
- Locale, keyboard, and account settings
- Firmware type (BIOS or UEFI)
- Recovery identity (unique run ID for rollback tracking)
- Sharing configuration (optional Windows/Linux file sharing)

**Two runtime-resolved fields** may be updated atomically after they become known:
- Staging partition identity (resolved during Windows-side preparation)
- UEFI boot-strategy fallback (resolved during firmware-specific preparation)

**Key files:**
- `Installation/InstallationPlan.cs` — Typed plan model
- `Installation/InstallationPlanFactory.cs` — Plan creation logic
- `Installation/InstallationPlanValidator.cs` — Validation rules (32KB, comprehensive)
- `Installation/InstallationPlanSerializer.cs` — JSON serialization/deserialization

### State Machine

A strict **14-step ordered state machine** governs the installation:

**Windows-phase steps (7):**
1. Preflight compatibility checks
2. Disk resize validation
3. Recovery guard setup
4. Hibernation policy adjustment
5. Staging area creation (FAT32 for BIOS, EFI partition for UEFI)
6. Media creation (live ISO + distribution ISO)
7. Temporary boot preparation (GRUB4DOS for BIOS, EFI variables for UEFI)

**Live-phase steps (4):**
8. Live preflight (plan revalidation against actual hardware)
9. Partition creation (ext4 on the target partition)
10. Distribution extraction and configuration
11. Bootloader installation (GRUB)

**Target-phase steps (3):**
12. System configuration (locale, keyboard, user account, packages)
13. Optional file sharing setup
14. Final verification and evidence publication

**Status transitions:**
```
pending → running → failed/succeeded/rollback-running → rolled-back
```

**Key properties:**
- 10 of 14 steps are compensatable (rollback-eligible)
- Only the next required step may start — out-of-order execution is rejected
- State is persisted to disk at each transition for crash recovery
- The state machine is implemented identically in C#, PowerShell, and Python

**Key files:**
- `Installation/InstallationStateMachine.cs` — 20KB, the core state machine
- `Installation/InstallationExecutionState.cs` — Current execution state
- `Installation/InstallationExecutionLedger.cs` — Audit trail of transitions
- `Installation/InstallationStateStore.cs` — Persistence layer

---

## 3. Windows↔Linux Communication

The handoff mechanism between the Windows application and the live Linux environment uses a **FAT staging volume**.

### How it works:

1. **Windows app writes** `installation-plan.json` and `installation-state.json` to a small FAT partition with a known volume label
2. **Live environment discovers** the staging volume by scanning block devices for the known label
3. **Live environment validates** both files against JSON schemas and verifies the plan's `planId` matches
4. **State transitions** are mirrored atomically back to the Windows volume for recovery access
5. **Windows verification** reads published evidence from the installed Linux system after first boot

### File flow:

```
Windows App                    FAT Staging Volume              Live Environment
     │                               │                              │
     ├── Write installation-plan.json ──►│                              │
     ├── Write installation-state.json ─►│                              │
     │                               │◄── Discover volume by label ───┤
     │                               │◄── Read + validate plan ───────┤
     │                               │◄── Read + validate state ──────┤
     │                               │                              │
     │◄── State transitions mirrored ─│◄── Write updated state ───────┤
     │                               │                              │
     │◄── Read published evidence ───│◄── Write evidence files ──────┤
```

### Why FAT?

- Readable by both Windows and Linux without additional drivers
- Simple, well-understood format
- Small partition size (tens of MB) keeps overhead minimal
- Known volume label enables reliable auto-discovery

---

## 4. UEFI/BIOS Handling

Libertix uses a **firmware adapter pattern** to cleanly separate shared logic from firmware-specific differences.

### Shared Live Runtime

The main live installer owns:
- Plan validation and revalidation
- Storage operations (partitioning, formatting, mounting)
- Distribution extraction and configuration
- State transitions and rollback orchestration
- Progress tracking and user feedback

### Firmware Adapters

Each adapter owns only the differences:

**BIOS Adapter (`libertix-bios-adapter.sh`):**
- MBR layout normalization and validation
- Boot code management (GRUB4DOS)
- BIOS-specific rollback procedures
- MBR boot flag management (`sfdisk --lock --activate`)
- Final verification (MBR partition count, boot flags, ext4 filesystem)

**UEFI Adapter (`libertix-uefi-adapter.sh`):**
- ESP (EFI System Partition) discovery and management
- Signed bootloader installation (shimx64.efi + grubx64.efi)
- Firmware entry management (BootNext/BootOrder)
- UEFI-specific rollback (firmware variable restoration)
- Final verification (ESP contents, EFI ownership markers, boot entries)

### BIOS Preparation (Windows-side)

`Pages/ApplyChanges.Bios.cs` (43KB) handles:
1. Recovery guard setup
2. Hibernation policy adjustment
3. Shrink validation (minimum 20 GiB)
4. FAT32 staging area creation
5. Live and distribution media creation
6. GRUB4DOS setup
7. Temporary BCD boot sequence modification

### UEFI Preparation (Windows-side)

`Pages/ApplyChanges.Uefi.cs` (34KB) + PowerShell modules handle:
1. Recovery guard setup
2. Shrink validation
3. Staging area creation (on existing EFI partition)
4. EFI media creation
5. Firmware variable manipulation
6. Transaction state persistence
7. Windows-side rollback capability

### ISO Architecture

Separate BIOS and UEFI ISOs are built via Docker:
- `iso/` — BIOS boot inputs and thin entry wrappers
- `iso-uefi/` — UEFI boot inputs and thin entry wrappers
- `iso-tools/build-isos-docker.sh` — Docker-based build process

Both ISO entry points are thin wrappers that select a firmware mode and execute the same shared runtime.

---

## 5. Live Environment Design

### Build Process

The live environment is built using Docker for reproducibility:
- No sudo required on the build host
- Deterministic environment
- CI-friendly

### Live Runtime Components

1. **Firmware adapters** — BIOS or UEFI specific handling
2. **Plan revalidation** — Re-checks the installation plan against actual hardware in the live environment
3. **Shared runtime** — Translations, progress tracking, storage operations
4. **Linux installer** — Inspects ISO, expands staging, creates filesystem, extracts and configures target system

### Target Configuration

The live installer:
- Inspects the distribution ISO
- Expands the staging area
- Creates the target filesystem (currently ext4)
- Extracts and configures the target system (locale, keyboard, user account, desktop)
- Installs and configures GRUB bootloader

### Key Scripts

- `assets/live/libertix-install-main.sh` — Main installation entry point
- `assets/live/libertix-bios-adapter.sh` — BIOS firmware adapter
- `assets/live/libertix-uefi-adapter.sh` — UEFI firmware adapter
- `assets/live/libertix-runner.sh` — Live environment runner

---

## 6. Rollback Mechanism

### Recovery Architecture

Recovery is armed **before the first mutating operation**. Each rollback action proves its target belongs to the current transaction by matching disk identity and exact partition geometry.

### Rollback Process

1. **Read persisted state** — Determine which steps have completed
2. **Compensate completed steps** — Undo operations in reverse order
3. **Restore Windows partition geometry** — Return disk to original state
4. **Restore boot code** — MBR (BIOS) or UEFI firmware entries
5. **Verify BitLocker state** — Ensure encryption is properly restored
6. **Verify recovery** — Confirm system is in a known-good state

### Compensatable Steps

10 of 14 installation steps are compensatable:
- Windows-side preparation steps (resize, staging, boot config)
- Live-phase steps (partitioning, extraction)
- Target-phase steps (configuration, bootloader)

### Post-Install Rollback

Successful installation does **not** erase rollback authority. A recovery session is maintained that allows rollback even after first boot, through a Windows-side verification agent.

### Recovery Guard

The recovery guard (`Scripts/libertix-recovery-guard.ps1`, 60KB) is a substantial PowerShell script that:
- Monitors the installation process
- Can trigger rollback if critical failures occur
- Persists recovery state for crash recovery
- Integrates with Windows System Restore

### Key Files

- `Scripts/libertix-recovery-guard.ps1` — Main recovery guard (60KB)
- `Scripts/libertix-uefi-recovery-agent.ps1` — UEFI-specific recovery (62KB)
- `Scripts/modules/` — Shared PowerShell functions for rollback
- `Installation/InstallationStateMachine.cs` — State transitions including rollback states

---

## 7. Artifact Verification

### Distribution Catalog

A signed distribution catalog (`catalog.json`) is fetched from GitHub Pages before any artifact download. The catalog contains:
- Distribution metadata (name, version, ISO URL)
- SHA-256 hashes for all artifacts
- RSA signature for integrity verification

### Verification Process

1. **Fetch catalog** — Download from signed GitHub Pages channel
2. **Verify signature** — RSA signature validation using bundled public key
3. **Download artifacts** — Distribution ISO, Libertix ISO, boot files
4. **Verify hashes** — SHA-256 hash verification for every downloaded component
5. **Local reuse** — Previously downloaded ISOs are validated by hash before reuse

### Trust Model

- Signing key is **offline** — only the public key is bundled
- Dev and main channels are **physically separated**
- Development filepool overrides are restricted to absolute HTTP/HTTPS URLs without credentials
- Stable builds verify signed `release.json` metadata and refuse to start if a newer version is published
- Development builds skip freshness checks but still verify the catalogue signature

### Key Files

- `Installation/ArtifactCatalog.cs` — Catalog model
- `Installation/DistributionCatalogLoader.cs` — Catalog fetching and parsing
- `Installation/DistributionCatalogTrust.cs` — Signature verification
- `Installation/ReleaseMetadata.cs` — Release version checking

---

## 8. Reuse Classification

### Can Be Reused Unmodified

| Component | Reason |
|-----------|--------|
| Installation plan model and validation | Generic, not distro-specific |
| State machine and execution ledger | Core infrastructure, distro-agnostic |
| Firmware adapter pattern | Architecture pattern, reusable as-is |
| Rollback engine (shared + firmware adapters) | Safety-critical, well-tested |
| Artifact verification and trust mechanism | Security infrastructure, reusable |
| Live environment runtime framework | Core infrastructure |
| JSON schemas | Contract definitions, reusable |
| Testing infrastructure framework | Test harness, reusable |

### Needs Distro-Specific Adaptation

| Component | What Changes |
|-----------|-------------|
| Distribution catalog | Add OintOS as a distribution entry |
| ISO build process | Build OintOS ISO (Ubuntu+KDE) instead of Mint/Zorin |
| Branding | Logo, splash screen, GRUB theme |
| Live environment GUI | OintOS branding if desired |
| Post-install verification | Verify OintOS-specific packages |
| First-boot verification | Integrate with OintOS OOBE wizard |

### Must Be Extended for OintOS

| Component | What's Needed |
|-----------|--------------|
| Filesystem support | Btrfs with snapshot/rollback (currently ext4 only) |
| Gaming stack | Steam, Proton, Wine, WinBoat integration |
| Kernel/mesa freshness | Layered gaming-optimized packages |
| OOBE wizard | Full guided first-boot experience |
| WinBoat integration | Windows compatibility layer setup |

---

## 9. Critical Open Question: Btrfs Support

**The single most significant adaptation needed** is Btrfs support. Libertix currently installs **ext4** as the target filesystem. OintOS requires **Btrfs with snapshot/rollback**.

### Options

1. **Add Btrfs to Libertix's target configuration scripts** — Modify the live installer to support Btrfs as an alternative filesystem. This is the cleanest approach but requires understanding the full target configuration pipeline.

2. **Separate Btrfs setup phase** — Install with ext4 first, then convert or add Btrfs subvolumes post-install. More complex but lower risk to Libertix's core flow.

3. **Build snapshot/rollback independently** — Use Timeshift or a custom Btrfs snapshot tool that operates independently of Libertix. Cleanest separation but may not integrate as tightly.

### Recommendation

This should be resolved during Phase 5 (Btrfs + snapshot/rollback integration) with a proof-of-concept. The architecture assessment should document this as the highest-priority adaptation item.

---

## 10. Summary of Key Patterns to Preserve

1. **Typed plans over imperative scripts** — The installation plan is a data document, not a script. All runtimes consume the same validated data.

2. **Multi-runtime state consistency** — The state machine is implemented identically in C#, PowerShell, and Python, with CI comparing all four copies.

3. **Contract-driven development** — JSON schemas are the machine-readable authority; runtime validators add only semantic invariants.

4. **Firmware adapter pattern** — Clean separation of shared logic from firmware-specific differences.

5. **Compensatable transactions** — Every mutating operation has a corresponding rollback action, proven by transaction identity.

6. **Pre-flight verification** — Both before and after any disk modification, the system validates expected vs. actual state.

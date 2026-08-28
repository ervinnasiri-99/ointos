# OintOS — Master Prompt for Claude Code

**Purpose of this document:** This is the complete requirements specification and build instruction for OintOS, an Ubuntu-based Linux distribution with a Windows-native installer. It was produced through a structured requirements interview and is intended to be pasted directly into a Claude Code session to begin implementation. It contains final decisions, open questions, architecture guidance, and development rules. Work incrementally — do not attempt to generate the entire project in one pass.

---

## 1. Executive Specification

OintOS is an Ubuntu 26.04 LTS-based Linux distribution built for a broad public audience — especially Windows users migrating away from Windows — that pairs a modern, loosely Windows-inspired KDE Plasma desktop with a **Windows-native installer**: a downloadable `.exe` that runs a graphical wizard directly inside Windows, performs safety checks, prepares the disk, and reboots into a Linux-side installation environment without requiring a USB stick. The Windows-side installer is a direct fork of the open-source [Libertix](https://github.com/ekimiateam/libertix/) project, adapted for OintOS.

OintOS prioritizes **stability and data safety above all else**, while still delivering CachyOS-level gaming performance (Steam, Proton, Wine, WinBoat pre-integrated) through selectively fresher kernel/mesa packages layered on the Ubuntu LTS base. Telemetry is entirely absent. The system uses Btrfs with snapshot/rollback support. Development happens primarily via Claude Code, with a Raspberry Pi 4 as the control/dev machine, an AMD Ryzen 5 5500/16GB/GTX 750 desktop as a local build machine, and GitHub Actions as CI where it fits free-tier limits.

---

## 2. Product Requirements

- Distro name: **OintOS**, Ubuntu 26.04 LTS ("Resolute Raccoon") base.
- Desktop environment: **KDE Plasma**, loosely Windows-inspired but modern (not a clone).
- Display server: installer lets the user choose Wayland or X11 at install time.
- Package strategy: **APT-first**; Flatpak and Snap available as extras, not primary.
- Default browser: **Brave**.
- Office suite: **user-selectable at install time** — LibreOffice, other suites, or none. The installer must clearly present **WinBoat** as the path to running Microsoft Office and other native Windows apps.
- Gaming: first-class, CachyOS-level support — Steam, Proton, and Wine pre-integrated and tuned, not merely installable.
- Compatibility layer: **WinBoat** installed alongside Proton/Wine for broader Windows application compatibility.
- Filesystem: **Btrfs**, with **Timeshift-style snapshot and rollback** support built in from the start.
- Telemetry: **none**, full stop. No opt-in tracking of any kind.
- Updates: OS updates are **notify + manual approval** — never silently automatic.
- First boot: a **full guided OOBE-style wizard** (accounts, theme, driver setup, network, app recommendations) — polished, commercial-OS-caliber experience, not a bare desktop drop.
- Default theme mode (light/dark): undecided — let the user choose during first boot.
- Target hardware: **broad** — Intel, AMD, NVIDIA, laptops and desktops, including older machines, not modern-only.
- Release channel: **stable only** for the initial phase; no nightly/beta yet.
- Release infrastructure: a **single GitHub monorepo** (installer + distro build configs + docs together) — no dedicated org, website, or mirrors yet.

### Windows Installer (Libertix Fork)
- Fork **Libertix directly** and adapt it for OintOS — not a from-scratch reimplementation.
- Install modes are **user-selectable at install time**: dual-boot alongside Windows, replace Windows, advanced/manual, etc. Do not hard-code a single flow.
- Online installation is **required** — components are downloaded during setup; no fully offline install mode is in scope for v1.
- The installer must let the user choose target disk, and where applicable, the specific Windows partition to modify.

---

## 3. Non-Functional Requirements

- **Safety over convenience**: every disk-modifying operation must be gated behind an explicit, human-readable confirmation. Never assume partition operations cannot fail — design for partial failure and recovery at every step.
- **Reliability**: the installer must handle interrupted installs (power loss, cancellation, unexpected reboot) gracefully, leaving the Windows system in a recoverable state wherever technically possible.
- **Security**: all downloaded artifacts (Linux components, ISO images, update packages) must be integrity- and signature-verified before use. No unauthenticated code execution paths.
- **Maintainability**: distro-specific code must be clearly separated from generic/forked Libertix installer code, to ease future upstream syncs.
- **Performance**: gaming-relevant packages (kernel, mesa, GPU drivers) should track meaningfully fresher versions than stock Ubuntu LTS, without destabilizing the rest of the base system.
- **Privacy**: zero telemetry, by architecture — not just by default setting.
- **Transparency**: build process, package origins, and signing must be auditable; nothing "mystery-meat."

---

## 4. Distribution Specification

- **Base**: Ubuntu 26.04 LTS ("Resolute Raccoon"). Note: this is a very recently released LTS (April 2026) with some early-life rough edges reported at release time (NVIDIA suspend/resume issues under Wayland on some hardware, incomplete installer screen-reader support). Claude Code should re-verify current known-issue status before hardware-support work in later phases, since these may already be patched.
- **Tracking depth**: moderate customization — curated default package set, some Ubuntu-specific tools swapped out (exact list TBD during Phase 4 defaults work), but not a from-scratch kernel/driver fork.
- **Desktop**: KDE Plasma on top of Ubuntu base packages.
- **Kernel/driver strategy**: layer a fresher kernel and/or mesa stack on top of Ubuntu LTS specifically for gaming-relevant components. Concretely evaluate (do not assume) options such as a maintained mainline/Liquorix/Xanmod-style kernel packaging approach, and a mesa PPA or Kisak-mesa-equivalent strategy, weighing stability risk against gaming performance gain. This is an **open technical decision** Claude Code should research and propose, not silently pick.
- **Branding**: logo, color palette, and visual mood are **fully open** — not yet decided. Do not invent final branding; use clearly-labeled placeholder branding and flag it for a dedicated design pass.
- **Package defaults not yet specified** (browser and office suite are decided; others such as terminal, file manager, PDF viewer, image viewer, text editor, media player are open) should default to sensible, well-maintained KDE-ecosystem choices unless the user specifies otherwise, and should be flagged as assumptions in commit/PR descriptions.

---

## 5. Installer Specification (Windows → Linux Flow)

1. User downloads a single `.exe` (name TBD — placeholder: `ointos-installer.exe`).
2. Graphical wizard launches; performs compatibility checks (architecture, firmware type, disk space, BitLocker status, Secure Boot status, TPM presence).
3. **BitLocker handling**: if BitLocker is detected, the installer must detect it and **require the user to decrypt or suspend it before proceeding** — no silent bypass, no proceeding with an encrypted target disk.
4. **Risky disk layouts** (RAID, dynamic disks, multiple existing Windows installations, unusual partition schemes): the installer **warns and lets the user decide** how to proceed — it must not silently auto-fix these, nor hard-abort without giving the user a path forward.
5. Installer detects disks/partitions and presents a **visual partition map** — this confirmation screen is **mandatory before any disk write**, with no way to skip it.
6. Installer creates a **Windows-side recovery/restore point** before making any changes.
7. User selects install mode (dual-boot / replace / alongside / advanced) and target disk/partition.
8. Installer downloads and verifies required Linux components (signature/hash verification required).
9. Installer configures the boot environment (bootloader choice deferred to Libertix's existing architecture — evaluate and document rather than reinvent).
10. System reboots directly into the Linux-side installation environment — **no USB required**.
11. Linux-side installer completes: filesystem setup (Btrfs), bootloader install, KDE Plasma + selected software, WinBoat/Proton/Wine setup, snapshot baseline creation.
12. System reboots into first-boot OOBE wizard.

---

## 6. Libertix Integration Specification

- **Approach**: fork Libertix directly rather than reimplementing from scratch.
- Before integration work begins, Claude Code must produce a written architecture assessment of the Libertix repository covering: overall structure, how installation plans/state transitions work, how the Windows app communicates with the Linux-side installer, how UEFI/BIOS are handled, how the live environment works, how rollback works, and how artifacts are verified.
- Based on that assessment, identify: what can be reused unmodified, what needs distro-specific adaptation, and what should be kept cleanly separated as "generic Libertix core" vs. "OintOS-specific" code, to ease future upstream syncing.
- **Licensing**: Libertix is GPL-3.0. Proceed on the assumption that the fork and any OintOS-specific installer code built on top of it must also be GPL-3.0-compatible and publicly available. This is **not yet legally reviewed** — flag it explicitly wherever licensing-sensitive code is touched, and do not obscure or attempt to work around GPL obligations.

---

## 7. Disk Safety Specification

**Non-negotiable principles:**
- No disk-modifying operation happens without an explicit, visual, human-reviewable confirmation immediately before it.
- BitLocker-encrypted disks are never touched without the user first decrypting/suspending encryption.
- A Windows-side recovery point is created before any disk change.
- Unusual/risky layouts (RAID, dynamic disks, multiple OS installs) trigger a warning and require explicit user decision — never a silent default action.
- The system must assume partition operations **can and will fail** at any step, and must be designed with recovery/rollback paths for interrupted installs (power loss, cancellation, unexpected reboot).
- Verification must occur **both before and after** any disk modification (pre-flight checks + post-write validation).
- Rollback mechanisms must exist wherever a change is made that could leave the system unbootable.

**Automatic operations that must NEVER happen without explicit confirmation:** partition creation/deletion/resizing, bootloader modification, disk formatting, BitLocker bypass attempts.

---

## 8. Linux Installer Specification

- Filesystem: **Btrfs**, configured from install time to support **Timeshift-style snapshots/rollback**.
- Live environment base, installer framework choice (Ubuntu's own installer vs. Calamares vs. custom) is an **open technical decision** — Claude Code should evaluate options against the "moderate Ubuntu tracking" and "broad hardware support" requirements and propose a recommendation with rationale before implementing.
- Bootloader: deferred to whatever Libertix's existing architecture uses; document the choice once determined rather than assuming GRUB or systemd-boot upfront.
- Secure Boot: support **both** Secure Boot and legacy/non-Secure-Boot systems, preferring Secure Boot when hardware supports it (signed boot components required in that path).
- Installation progress, logs, and failure handling must be user-visible and diagnosable — avoid silent failures.
- System must be validated before the final reboot into the installed OS (integrity checks on installed files, bootloader presence, etc.).

---

## 9. First-Boot Specification

- Full **OOBE-style guided wizard**: account creation, timezone/language/keyboard setup, Wi-Fi/Bluetooth setup, hardware/driver detection (NVIDIA/AMD as applicable), theme selection (light/dark — not pre-decided), default application confirmation, and privacy settings (trivial here, since telemetry is off by design — this screen should state that plainly rather than offer a toggle that implies telemetry exists).
- Should feel like a polished, commercial-grade OS setup experience — not a bare KDE first-login.

---

## 10. Build Infrastructure

- **Raspberry Pi 4**: primary development/control environment for Claude Code, not necessarily where expensive builds run.
- **AMD Ryzen 5 5500 / 16GB RAM / GTX 750 desktop**: available as a more capable local build machine for heavier build/test tasks.
- **GitHub Actions**: preferred CI/build path **if it fits within free-tier limits** (notably ~14GB usable runner disk space and free-tier minute limits). Claude Code must explicitly verify whether a full OintOS ISO build (Ubuntu base + KDE + gaming stack + Btrfs tooling) fits within these constraints before committing to a GitHub-Actions-only build pipeline — this is a real, named risk (see Section 16).
- If GitHub Actions free-tier limits are insufficient, propose a hybrid approach: CI for lighter validation/lint/test tasks, and the local Ryzen desktop for full ISO builds.

---

## 11. Repository Architecture

- **Monorepo** structure — installer code, distro build configuration, and documentation live together in a single GitHub repository (no split multi-repo setup for v1).
- Proposed top-level layout (adjust as implementation reveals better structure — treat this as a starting point, not gospel):

```
ointos/
├── README.md
├── docs/                      # architecture decisions, specs, this master prompt's living successor
├── windows-installer/         # forked/adapted Libertix code, clearly marked distro-specific vs. upstream
│   ├── upstream/               # minimally-modified Libertix core (for easier upstream sync)
│   └── ointos/                 # OintOS-specific adaptations, branding, config
├── linux-installer/            # live environment / installation engine config
├── distro-build/               # ISO build scripts, package lists, live-build or equivalent config
├── branding/                   # placeholder branding assets (logo/theme/wallpapers) — flagged as TBD
├── first-boot/                 # OOBE wizard implementation
├── ci/                         # GitHub Actions workflows
└── tests/                      # unit, integration, VM test harnesses
```

---

## 12. Development Phases

```text
Phase 1 — Requirements (this document — complete)
Phase 2 — Libertix architecture assessment & integration plan
Phase 3 — Ubuntu 26.04 + KDE Plasma prototype (headless/manual build, no installer yet)
Phase 4 — Distro build system (ISO build automation, package curation)
Phase 5 — Btrfs + snapshot/rollback integration
Phase 6 — Linux-side live installer (framework decision + implementation)
Phase 7 — Windows-side installer (Libertix fork adaptation)
Phase 8 — Disk safety layer (confirmation flows, BitLocker handling, recovery points, risky-layout warnings)
Phase 9 — Gaming stack integration (Steam, Proton, Wine, WinBoat, kernel/mesa freshness strategy)
Phase 10 — First-boot OOBE wizard
Phase 11 — Testing infrastructure (unit/integration/VM layers)
Phase 12 — CI/build infrastructure finalization (GitHub Actions feasibility, local build fallback)
Phase 13 — Hardware validation pass (broad Intel/AMD/NVIDIA coverage)
Phase 14 — Branding pass (once direction is provided)
Phase 15 — Release infrastructure & stable channel cut
```

Each phase should conclude with working, tested, committed state before moving to the next. Do not skip ahead into later phases while earlier ones are unresolved.

---

## 13. Testing Strategy

**Unit tests**: individual installer logic components (disk detection, partition math, BitLocker/Secure Boot detection, signature verification routines).

**Integration tests**: full installer flows against simulated disk states (clean disk, existing Windows install, encrypted disk, risky layouts) in automated environments.

**VM testing** (primary testing method for now, per current decision — no physical hardware testing planned yet):
- Windows 10 and Windows 11 VMs, covering UEFI and legacy BIOS, GPT and MBR, with and without BitLocker, single and multiple disks, varied partition layouts, insufficient disk space scenarios, simulated failed/corrupted downloads, and interrupted/cancelled installations.
- Linux-side: boot, install, networking, audio, graphics, suspend, Bluetooth, package management, and desktop functionality in VM environments.

**Hardware testing**: explicitly out of scope for the current phase (VM-only per current decision) — but the test harness should be designed so hardware-in-the-loop testing can be added later without a rewrite, since "broad hardware support" is a stated goal and VM testing alone will not catch real driver/firmware issues.

**What must be automated wherever possible**: BitLocker detection, risky-layout warning triggers, confirmation-screen gating (i.e., verify no disk write can occur without confirmation), rollback correctness after simulated interruption.

---

## 14. Security Model

- All downloaded installer components, ISO images, and update packages must be **signature- and hash-verified** before use (SHA-256 minimum, GPG signing for release artifacts).
- The Windows-side installer requires elevated (administrator) privileges — scope what it does with that privilege tightly, log privileged operations, and avoid unnecessary PowerShell/script execution surface.
- Repository/package signing must be maintained for any OintOS-specific APT repository introduced.
- Update mechanism must verify authenticity before applying anything, consistent with the "notify + manual approval" update model.
- Supply-chain security: pin and verify sources for anything pulled from third-party repos (e.g., gaming kernel/mesa sources) rather than trusting arbitrary upstream mirrors.
- No telemetry, and therefore no telemetry-related data security surface to defend (an explicit non-goal, not an oversight).

---

## 15. Licensing Considerations

- **Libertix (GPL-3.0)**: forking it obligates the OintOS Windows installer code to remain GPL-3.0 (or compatible) and publicly available. This has been accepted provisionally, **pending legal review** — flag this clearly in the repo (e.g., a LICENSE-NOTES.md) and do not take any action that would be harder to unwind if legal review later requires changes (e.g., avoid mixing in incompatible proprietary code).
- **Ubuntu trademarks**: OintOS branding/marketing must respect Canonical's trademark policy — avoid implying official endorsement.
- **Third-party package licenses**: standard Ubuntu package licensing applies; no special action needed beyond normal distro practice, but flag anything unusual encountered.
- **Fonts, icons, wallpapers**: since branding is currently undecided, ensure any placeholder assets used are themselves properly licensed for redistribution — do not use unlicensed assets even as placeholders.
- **WinBoat, Proton, Wine**: verify licensing compatibility for bundling/pre-integrating each, and flag anything requiring attribution or additional notices.

---

## 16. Known Risks

1. **GitHub Actions free-tier feasibility**: A full OintOS ISO build (Ubuntu base + KDE + gaming stack + Btrfs tooling) may exceed GitHub's free-tier runner disk space (~14GB) and/or minute limits. Mitigation: verify early (Phase 12), have the Ryzen 5500 desktop as a fallback local build path.
2. **Gaming-freshness vs. LTS-stability tension**: Layering rolling-release-style kernel/mesa packages onto an Ubuntu LTS base is nontrivial and can introduce instability that conflicts with the "stability & safety first" priority. Mitigation: research and propose a specific, bounded strategy (e.g., a maintained kernel PPA/channel + a mesa PPA), rather than a broad rolling-release overlay, and test thoroughly before shipping as default.
3. **Very young LTS base (Ubuntu 26.04)**: Released April 2026, this LTS may still have unresolved hardware-compatibility issues (e.g., NVIDIA suspend/resume) at the time of implementation. Mitigation: re-check current known-issue status before/during Phase 13 hardware validation.
4. **VM-only testing before broad hardware claims**: "Broad hardware support" is a stated goal, but testing is currently VM-only. Mitigation: be explicit in release notes/docs about what's actually been validated vs. claimed, until hardware testing is added.
5. **GPL-3.0 obligations not yet legally reviewed**: proceeding on an assumption carries risk if that assumption is wrong. Mitigation: keep OintOS-specific code cleanly separated from upstream Libertix code, avoid mixing in incompatible licensing, and get this reviewed before any public release.
6. **Undecided bootloader/live-installer-framework choices**: several core technical decisions (bootloader, live installer framework) are deliberately deferred to "whatever Libertix uses" or "TBD" — these need to be resolved with actual investigation, not assumption, early in Phase 2/6, since much else depends on them.
7. **Monorepo scaling**: a single monorepo for installer + distro build + docs is fine at this scale but may need re-evaluation if the Windows installer and Linux distro build diverge significantly in tooling/CI needs later.

---

## 17. Claude Code Development Rules

While implementing this project, Claude Code must:

1. **Inspect before modifying** — always read and understand existing code/config before changing it, especially anything touching disk operations or the Libertix fork.
2. **Never blindly overwrite files** — preserve working functionality; diff-review changes conceptually before applying them.
3. **Make incremental commits** — one milestone/logical change per commit, with clear messages explaining the "why," not just the "what."
4. **Test changes** — run relevant tests (unit/integration/VM as applicable) after each milestone before moving on.
5. **Document architectural decisions** — especially for the currently-open items (bootloader choice, live installer framework, kernel/mesa freshness strategy) — write these decisions down with rationale when made.
6. **Never perform destructive disk operations on development machines** — all disk-modifying code must be tested exclusively against VMs or disposable test disks/images, never against the Pi 4, the Ryzen desktop, or any machine actually used for development.
7. **Never assume hardware** — write hardware-detection code defensively; do not hard-code assumptions about GPU vendor, firmware type, or disk configuration.
8. **Verify downloaded artifacts** — every download (Linux components, packages, ISO images) must be signature/hash-verified before use; never trust an unverified download path, even during development/testing.
9. **Keep distro-specific code separated from generic installer code** — maintain the upstream/ vs. ointos/ separation in the Libertix fork (and equivalent separations elsewhere) to ease maintenance and future upstream syncing.
10. **Maintain rollback behavior** — any feature that can leave a system in a partially-modified state must have a corresponding rollback/recovery path, tested.
11. **Do not silently bypass failed safety checks** — a failed BitLocker check, a failed signature verification, a failed disk-safety confirmation must halt the relevant flow, not proceed with a warning-only log.
12. **Work incrementally** — implement one milestone/phase at a time per Section 12; do not attempt to generate the entire project in one response or one session.
13. **Stop and ask when genuinely ambiguous** — when a requirement cannot be safely inferred from this document (e.g., final bootloader choice, live installer framework, kernel/mesa strategy specifics, branding specifics), stop and request clarification rather than guessing silently. Sensible defaults are fine for genuinely low-stakes details (e.g., default terminal emulator), but not for anything touching disk safety, licensing, or core architecture.
14. **Use VMs/test disks for all installer testing** — per current project decision, no physical hardware testing is in scope yet; do not test disk-modifying code against real hardware without explicit new instruction.

---

## 18. THE MASTER PROMPT (paste directly into Claude Code)

```
You are working on OintOS, an Ubuntu 26.04 LTS-based Linux distribution with a
Windows-native installer forked from the open-source Libertix project
(https://github.com/ekimiateam/libertix/). Full requirements are documented in
this Master Prompt — treat it as your primary spec. Where this document marks
something as an open technical decision, research it and propose an answer
with rationale before implementing; do not guess silently on anything touching
disk safety, licensing, or core architecture (bootloader choice, live
installer framework, kernel/mesa freshness strategy). For genuinely low-stakes
details not covered here, use sensible defaults and note the assumption.

PROJECT SUMMARY
OintOS pairs a modern, loosely Windows-inspired KDE Plasma desktop (Ubuntu
26.04 LTS base, moderate customization depth) with a Windows-native installer:
a downloadable .exe that runs a graphical wizard inside Windows, performs
safety checks (including BitLocker detection requiring decrypt/suspend before
proceeding, and warnings on risky disk layouts like RAID/dynamic disks/
multiple Windows installs), creates a Windows-side recovery point, shows a
mandatory visual partition-map confirmation before any disk write, prepares
the disk, downloads and verifies Linux components online, configures the boot
environment, and reboots directly into a Linux-side installer — no USB
required. Target audience is the broader public, especially Windows users
migrating to Linux. Stability and data safety are the top priority in every
trade-off. Telemetry is entirely absent.

KEY DECISIONS ALREADY MADE (do not re-litigate these; implement against them)
- Distro name: OintOS
- Base: Ubuntu 26.04 LTS "Resolute Raccoon"
- Desktop: KDE Plasma, loosely Windows-inspired, not a clone
- Display server: user chooses Wayland or X11 at install time
- Filesystem: Btrfs with Timeshift-style snapshot/rollback
- Package strategy: APT-first, Flatpak/Snap as extras
- Browser: Brave
- Office: user-selectable at install (LibreOffice/alternatives/none);
  WinBoat presented as the path to Microsoft Office
- Gaming: first-class, CachyOS-level (Steam, Proton, Wine pre-integrated),
  plus WinBoat for broader Windows app compatibility
- Kernel/mesa: deliberately fresher than stock Ubuntu LTS for gaming
  packages specifically — needs a researched, bounded implementation
  strategy, not a blanket rolling-release overlay
- Windows installer: direct Libertix fork, kept cleanly separated
  (upstream/ vs ointos/) for future sync-ability
- Install modes: user-selectable (dual-boot/replace/alongside/advanced)
- Connectivity: online install required, no offline mode in v1
- Secure Boot: support both Secure Boot and legacy, prefer Secure Boot
- Updates: notify + manual approval, never silently automatic
- First boot: full OOBE wizard (accounts, theme, drivers, network, apps)
- Telemetry: none, by architecture
- Licensing: proceed assuming GPL-3.0 compatibility for the Libertix fork;
  flagged for legal review, not yet resolved — keep code separation clean
  to preserve optionality
- Repo: single GitHub monorepo (installer + distro-build + docs together)
- Release: stable channel only for now
- Hardware target: broad (Intel/AMD/NVIDIA, laptop+desktop, older PCs)
- Testing: VM-only for now (Windows 10/11, UEFI/BIOS, GPT/MBR, BitLocker
  on/off, multiple disks, varied layouts, interrupted installs); hardware
  testing explicitly out of scope until later
- Dev environment: Raspberry Pi 4 = control/dev machine; Ryzen 5 5500 /
  16GB / GTX 750 desktop = local build machine; GitHub Actions preferred
  for CI if it fits free-tier limits (~14GB runner disk) — verify this
  explicitly before committing to it as the sole build path

NAMED RISKS TO KEEP IN MIND
1. GitHub Actions free-tier disk/minute limits may not fit a full ISO build
   — verify early, have the Ryzen desktop as fallback.
2. Gaming-freshness kernel/mesa layering on an LTS base can destabilize the
   system — needs a specific, bounded, well-tested strategy.
3. Ubuntu 26.04 is a young LTS (April 2026) — re-check current known-issue
   status (e.g., NVIDIA suspend/resume) before hardware validation work.
4. "Broad hardware support" is a goal but testing is VM-only for now — be
   explicit in docs about what's actually validated vs. claimed.
5. GPL-3.0 obligations for the Libertix fork are assumed, not yet legally
   reviewed — keep upstream/distro-specific code cleanly separated.
6. Bootloader and live-installer-framework choices are open — resolve with
   real investigation early, since much else depends on them.

DEVELOPMENT RULES (non-negotiable)
1. Inspect before modifying; never blindly overwrite files.
2. Make incremental commits with clear rationale.
3. Test after every milestone (unit/integration/VM as applicable).
4. Document architectural decisions as you make them, especially the open
   items listed above.
5. NEVER perform destructive disk operations on development machines (the
   Pi 4 or the Ryzen desktop) — all disk-modifying code is tested only
   against VMs or disposable test disks/images.
6. Never assume hardware — detect defensively (GPU vendor, firmware type,
   disk configuration).
7. Verify every downloaded artifact (signature/hash) before use, including
   during development/testing.
8. Keep distro-specific code separated from generic/forked installer code
   (upstream/ vs ointos/ pattern).
9. Maintain rollback/recovery paths for anything that can leave a system
   partially modified.
10. Never silently bypass a failed safety check (BitLocker check, signature
    verification, disk-safety confirmation) — halt the relevant flow.
11. Work one milestone at a time — do not attempt the whole project in one
    session or one giant response.
12. Stop and ask for clarification whenever a requirement genuinely cannot
    be inferred safely — especially anything touching disk safety,
    licensing, or core architecture.

DEVELOPMENT PHASES (work through these in order; complete and test each
before moving to the next)
Phase 1 — Requirements (this document) — COMPLETE
Phase 2 — Libertix architecture assessment & integration plan
Phase 3 — Ubuntu 26.04 + KDE Plasma prototype (manual/headless build)
Phase 4 — Distro build system (ISO build automation, curated package list)
Phase 5 — Btrfs + snapshot/rollback integration
Phase 6 — Linux-side live installer (framework decision + implementation)
Phase 7 — Windows-side installer (Libertix fork adaptation)
Phase 8 — Disk safety layer (confirmations, BitLocker handling, recovery
          points, risky-layout warnings)
Phase 9 — Gaming stack integration (Steam/Proton/Wine/WinBoat, kernel/mesa
          freshness strategy)
Phase 10 — First-boot OOBE wizard
Phase 11 — Testing infrastructure (unit/integration/VM layers)
Phase 12 — CI/build infrastructure finalization
Phase 13 — Hardware validation pass
Phase 14 — Branding pass (once branding direction is provided — currently
           fully open, use clearly-labeled placeholders until then)
Phase 15 — Release infrastructure & stable channel cut

YOUR FIRST STEPS
1. Inspect any existing repository state (if one exists) and summarize what's
   there before touching anything.
2. Set up the monorepo skeleton per the proposed layout in Section 11 of the
   full spec document (windows-installer/, linux-installer/, distro-build/,
   branding/, first-boot/, ci/, tests/, docs/) — adjust if you find good
   reason to, but document why.
3. Begin Phase 2: fetch and study the Libertix repository, and produce a
   written architecture assessment (structure, install-plan/state-machine
   design, Windows↔Linux-side communication, UEFI/BIOS handling, live
   environment design, rollback mechanism, artifact verification) before
   writing any integration code.
4. Propose a specific plan for the kernel/mesa freshness strategy (risk #2
   above) with concrete options and trade-offs before implementing it.
5. Stop and report back after Phase 2's architecture assessment is complete,
   rather than proceeding straight into implementation — this is a natural
   checkpoint to confirm direction before larger amounts of code get written.
```

# OintOS — Claude Code Project Context

## What is this project?

OintOS is an Ubuntu 26.04 LTS-based Linux distribution with a Windows-native installer forked from the open-source Libertix project. Full requirements are in `docs/master-prompt.md`.

## Current phase

Phase 6 — Linux-side live installer (Calamares). Framework decision: **Calamares** (`docs/decisions/007-linux-installer-calamares.md`). Installer code in `linux-installer/` (settings-ointos package, launcher, unattended plan driver). Needs a VM install test (interactive + unattended).

## Key rules

1. Read and understand existing code before modifying it
2. Incremental commits with clear rationale
3. Test after every milestone
4. Document architectural decisions, especially open items
5. NEVER perform destructive disk operations on dev machines
6. Never assume hardware — detect defensively
7. Verify every downloaded artifact before use
8. Keep distro-specific code separated from generic/forked installer code
9. Maintain rollback/recovery paths for anything that can leave a system partially modified
10. Never silently bypass a failed safety check

## Repository layout

```
docs/                      # Architecture decisions, specs
windows-installer/         # Forked Libertix code (upstream/ + ointos/)
linux-installer/           # Live environment / installation engine
distro-build/              # ISO build scripts, package lists
branding/                  # Logo, theme, wallpapers (TBD)
first-boot/                # OOBE wizard
ci/                        # GitHub Actions workflows
tests/                     # Unit, integration, VM test harnesses
```

## Open technical decisions

- Bootloader choice: deferred to Libertix's existing architecture (GRUB)
- Live installer framework: TBD (evaluate against requirements)
- Kernel/mesa freshness strategy: proposed in `docs/decisions/001-kernel-mesa-strategy.md`
- Branding: fully open, use clearly-labeled placeholders

## Dev environment

- Raspberry Pi 4: primary dev/control machine
- AMD Ryzen 5 5500 / 16GB / GTX 750: local build machine
- GitHub Actions: CI if free-tier limits allow

## Important files

- `docs/master-prompt.md` — Full requirements spec
- `docs/architecture/001-libertix-assessment.md` — Libertix architecture analysis
- `docs/decisions/001-kernel-mesa-strategy.md` — Kernel/mesa strategy
- `docs/decisions/002-libertix-fork-strategy.md` — Libertix fork approach
- `docs/decisions/004-build-pipeline-casper.md` — casper build pipeline (replaces live-build)
- `docs/decisions/007-linux-installer-calamares.md` — Calamares installer decision
- `distro-build/isobuild.sh` — Main ISO build script (casper pipeline)
- `distro-build/dockerbuild.sh` — Runs the build in an isolated container (safe path)
- `linux-installer/calamares-settings-ointos/` — branded Calamares config
- `linux-installer/launcher/ointos-installer-prompt` — live-session installer launcher
- `linux-installer/unattended/plan.py` — unattended install plan driver (Windows-handoff)
- `distro-build/otest.sh` `otest2.sh` `otest3.sh` `otest4.sh` — VM acceptance tests
- `LICENSE-NOTES.md` — GPL-3.0 obligations and legal review status

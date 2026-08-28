# OintOS — Claude Code Project Context

## What is this project?

OintOS is an Ubuntu 26.04 LTS-based Linux distribution with a Windows-native installer forked from the open-source Libertix project. Full requirements are in `docs/master-prompt.md`.

## Current phase

Phase 3 — Ubuntu 26.04 + KDE Plasma prototype build (in progress).

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
- `docs/decisions/001-kernel-mesa-strategy.md` — Kernel/mesa strategy proposal
- `docs/decisions/002-libertix-fork-strategy.md` — Fork approach documentation
- `docs/decisions/003-build-tool-choice.md` — Build tool decision (live-build)
- `distro-build/build.sh` — Main ISO build script
- `distro-build/config/` — live-build configuration (package lists, hooks)
- `LICENSE-NOTES.md` — GPL-3.0 obligations and legal review status

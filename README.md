# OintOS

An Ubuntu 26.04 LTS-based Linux distribution with a Windows-native installer.

## What is OintOS?

OintOS is a Linux distribution built for a broad public audience — especially Windows users migrating away from Windows. It pairs a modern KDE Plasma desktop with a Windows-native installer: a downloadable `.exe` that runs a graphical wizard directly inside Windows, performs safety checks, prepares the disk, and reboots into a Linux-side installation environment — no USB stick required.

## Key Features

- **Windows-native installer** — forked from the open-source [Libertix](https://github.com/ekimiateam/libertix/) project
- **Ubuntu 26.04 LTS base** — "Resolute Raccoon", supported until April 2031
- **KDE Plasma desktop** — loosely Windows-inspired, modern and familiar
- **Btrfs filesystem** — with built-in snapshot and rollback support
- **Gaming-first** — Steam, Proton, Wine, and WinBoat pre-integrated
- **Zero telemetry** — by architecture, not just by default
- **Broad hardware support** — Intel, AMD, NVIDIA, laptops and desktops

## Project Status

**Phase 1 (Requirements):** Complete
**Phase 2 (Libertix Assessment):** In Progress

## Repository Structure

```
ointos/
├── docs/                      # Architecture decisions, specs, documentation
├── windows-installer/         # Forked/adapted Libertix code
│   ├── upstream/               # Minimally-modified Libertix core
│   └── ointos/                 # OintOS-specific adaptations
├── linux-installer/           # Live environment / installation engine
├── distro-build/              # ISO build scripts, package lists
├── branding/                  # Logo, theme, wallpapers (TBD)
├── first-boot/                # OOBE wizard implementation
├── ci/                        # GitHub Actions workflows
└── tests/                     # Unit, integration, VM test harnesses
```

## License

This project is licensed under the GNU General Public License v3.0, consistent with the Libertix upstream project. See [LICENSE-NOTES.md](LICENSE-NOTES.md) for licensing details and legal review status.

## Documentation

- [Master Prompt (Full Spec)](docs/master-prompt.md)
- [Libertix Architecture Assessment](docs/architecture/001-libertix-assessment.md)
- [Kernel/Mesa Strategy Decision](docs/decisions/001-kernel-mesa-strategy.md)
- [Libertix Fork Strategy](docs/decisions/002-libertix-fork-strategy.md)

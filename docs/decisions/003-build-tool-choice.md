# Build Tool Choice: live-build

**Date:** 2026-08-28
**Status:** Decision record
**Phase:** 3 — Ubuntu 26.04 + KDE Plasma prototype

---

## Decision

Use **live-build** as the primary ISO build tool for OintOS.

## Options Evaluated

| Tool | Headless | Ubuntu 26.04 | Hook System | CI Compatible | Maintained |
|------|----------|-------------|-------------|---------------|------------|
| **live-build** | Yes (native) | Yes | Excellent | Good | Yes (Debian/Ubuntu) |
| cubic | No (GUI only) | Yes | Limited | No | Yes |
| ubuntu-builder | Yes | Unlikely | Minimal | Poor | No (since ~2018) |
| Docker-based | Yes | Yes | Dockerfile | Excellent | N/A |
| Manual debootstrap | Yes | Yes | Manual | Moderate | N/A |

## Rationale

1. **Headless/CLI native** — Works on both the Pi 4 (control) and Ryzen desktop (build) without GUI
2. **Ubuntu's own tool** — Canonical uses it internally; maximum compatibility
3. **Extensive hook system** — Clean organization for Brave, gaming, telemetry removal
4. **Package list management** — Version-controlled, easy to curate
5. **Repository-friendly** — `config/` tree maps directly to git
6. **Proven at scale** — Used for all official Ubuntu flavors

## Build Machine Allocation

| Task | Machine | Rationale |
|------|---------|-----------|
| Development, git | Raspberry Pi 4 | Low-power, always-on |
| ISO builds | Ryzen 5 5500 | Needs 15-25GB disk, 30-90 min |
| CI validation | GitHub Actions | Lint, package validation |

## Rollback

If live-build has issues with Ubuntu 26.04, fallback to Docker-based approach (similar to Libertix's `iso-tools/build-isos-docker.sh`).

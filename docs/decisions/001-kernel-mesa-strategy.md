# Kernel/Mesa Freshness Strategy

**Date:** 2026-08-28
**Status:** Proposal — to be validated in Phase 9
**Risk addressed:** Risk #2 from master prompt — Gaming-freshness vs. LTS-stability tension

---

## Problem

OintOS needs CachyOS-level gaming performance (fresh kernel, modern mesa, gaming-optimized scheduling) on an Ubuntu 26.04 LTS base, without destabilizing the system for general use.

**Constraints:**
- "Stability and data safety above all else" — cannot compromise base system reliability
- Ubuntu 26.04 LTS ships kernel 7.0.0-30 and btrfs-progs 6.17.1 — already fairly fresh
- NTSYNC driver is available in 26.04 (good for Wine/Proton)
- Btrfs support is solid in 26.04
- Must be a bounded, maintainable strategy — not a full rolling-release overlay

---

## What Ubuntu 26.04 Already Provides

| Component | Version | Notes |
|-----------|---------|-------|
| Kernel | 7.0.0-30-generic | Very recent (released 2026) |
| Mesa | 25.x (TBD) | Check PPA availability |
| NTSYNC | Available | Good for Wine/Proton |
| Btrfs | 6.17.1 | Solid support |
| KDE Plasma | Available via Kubuntu | KDE 6.x |
| Steam/Proton | Installable via APT/Flatpak | Not pre-integrated |

**Key insight:** Ubuntu 26.04 is already quite fresh. The gap between stock Ubuntu and CachyOS may be smaller than with older LTS releases.

---

## Options Evaluated

### Option 1: Stock Ubuntu 26.04 Kernel + Mesa (Lowest Risk)

**What:** Use the Ubuntu 7.0 kernel and default mesa stack as-is. Only pre-integrate Steam, Proton, Wine, and WinBoat.

**Pros:**
- Zero added stability risk
- Full Ubuntu security update compatibility
- Simplest to maintain
- No PPA dependency

**Cons:**
- May miss CachyOS-level optimizations (BORE scheduler, wine-tkg patches)
- Mesa may be slightly behind gaming-optimized builds
- No kernel-level gaming tweaks

**Risk level:** Minimal

### Option 2: Ubuntu 26.04 Kernel + Mesa PPA (Moderate Risk)

**What:** Keep the Ubuntu 7.0 kernel but use a newer mesa from a PPA (e.g., kisak-mesa or oibaf) for better GPU performance.

**Pros:**
- Better GPU performance for gaming
- Low risk — mesa is userspace, failures don't crash the system
- Easy to revert (PPA removal)
- Ubuntu kernel maintains stability

**Cons:**
- PPA dependency for mesa updates
- Mesa updates may occasionally introduce regressions
- Need to verify mesa PPA is maintained for 26.04

**Risk level:** Low-Moderate

### Option 3: Xanmod or Liquorix Kernel (Moderate Risk)

**What:** Replace the Ubuntu kernel with a gaming-optimized kernel (Xanmod or Liquorix) while keeping Ubuntu's mesa.

**Pros:**
- Gaming-optimized scheduler (BORE/EEVDF)
- Lower latency, better frame pacing
- Well-maintained community kernels

**Cons:**
- Kernel replacement is higher risk than mesa swap
- May not receive Ubuntu security patches as quickly
- Can break kernel module compatibility (NVIDIA drivers, etc.)
- Harder to revert if issues arise

**Risk level:** Moderate-High

### Option 4: Ubuntu Kernel + Targeted Scheduler Patches (Moderate Risk)

**What:** Keep the Ubuntu 7.0 kernel but apply targeted BORE (Burst-Oriented Response Enhancer) scheduler patches for better gaming responsiveness.

**Pros:**
- Gaming-optimized scheduling without full kernel replacement
- Ubuntu security patches still apply
- More targeted than a full kernel swap

**Cons:**
- Requires maintaining patched kernel packages
- Patch compatibility with new kernel versions needs verification
- More complex build/maintenance process

**Risk level:** Moderate

### Option 5: CachyOS-Style Full Overlay (High Risk)

**What:** Layer CachyOS-style kernel, mesa, and gaming optimizations as a comprehensive overlay.

**Pros:**
- Closest to CachyOS gaming performance
- Comprehensive gaming optimization

**Cons:**
- High maintenance burden
- Significant stability risk
- Conflicts with "stability above all else" priority
- Hard to maintain alongside Ubuntu LTS updates
- Large surface area for regressions

**Risk level:** High

---

## Recommendation

### Phase 1 (Initial Release): Option 2 — Stock Kernel + Mesa PPA

**Rationale:**

1. Ubuntu 26.04 already ships kernel 7.0 with NTSYNC — the kernel is fresh enough
2. Mesa is the most impactful component for gaming GPU performance, and it's userspace (low risk)
3. A mesa PPA (kisak-mesa or equivalent) provides meaningful gaming performance gains with minimal stability risk
4. Steam, Proton, Wine, and WinBoat are pre-integrated on top of this base
5. This is the simplest strategy that delivers meaningful gaming performance

### Specific Implementation

```
Base: Ubuntu 26.04 LTS kernel 7.0.0-30-generic
Mesa: PPA source (kisak-mesa or equivalent, to be verified)
Gaming stack: Steam, Proton, Wine, WinBoat pre-installed
NTSYNC: Enabled by default (available in 26.04 kernel)
```

### Phase 2 (Post-Release Evaluation): Consider Option 4

After initial release and gaming benchmarks, evaluate whether targeted BORE scheduler patches provide meaningful enough gains to justify the maintenance cost. This should be data-driven, not assumption-driven.

**Benchmark criteria:**
- Frame pacing consistency (1% and 0.1% lows)
- Input latency
- Multi-game compatibility
- System stability over extended gaming sessions

### Rollback Plan

If the mesa PPA causes issues:
1. Remove PPA: `sudo add-apt-repository --remove ppa:kisak/mesa`
2. Downgrade: `sudo apt install libgl1-mesa-dri=26.0.4~ubuntu26.04.1~ppa1`
3. Reboot

If kernel patches (future) cause issues:
1. Boot previous kernel from GRUB advanced options
2. Remove patched kernel package
3. Reboot

---

## Open Questions

1. **Which mesa PPA to use?** — kisak-mesa, oibaf, or a custom PPA? Need to verify maintenance status and 26.04 compatibility during Phase 9.

2. **Mesa version target?** — How far ahead of stock Ubuntu mesa should we go? Conservative (1-2 point releases) vs. aggressive (latest stable)?

3. **NVIDIA driver strategy?** — Should we use Ubuntu's packaged NVIDIA drivers, NVIDIA's official PPA, or a third-party source? This interacts with the kernel/mesa strategy.

4. **Proton version pinning?** — Which Proton version to pre-install? Latest stable GE-Proton, official Proton, or both?

5. **WinBoat integration depth?** — How tightly should WinBoat integrate with the kernel/mesa stack? Does it need specific kernel configs?

---

## Decision Record

| Field | Value |
|-------|-------|
| Decision | Use stock Ubuntu 26.04 kernel + mesa PPA for initial release |
| Status | Proposed — to be validated in Phase 9 |
| Risk level | Low-Moderate |
| Rollback available | Yes (PPA removal + package downgrade) |
| Revisit trigger | After Phase 9 gaming benchmarks |
| Next action | Verify mesa PPA availability and maintenance status for 26.04 |

#!/bin/bash
# ============================================================================
# otest4.sh — installer acceptance test (Phase 6)
#
# Run AFTER a Calamares install (interactive or unattended) has written a
# system, FROM THAT INSTALLED SYSTEM (chroot or live side). Verifies:
#   A. ext4 root, no btrfs leftovers (decision 008)
#   B. GRUB bootloader + os-prober present
#   C. User + sudo group (from install)
#   D. No timeshift/btrfs tooling (decision 008)
#   E. No snapd; system is APT-first
#   F. Installer artifacts (calamares config, /etc/ointos-installed)
#
# Usage (from inside the installed root, or chroot):
#   bash otest4.sh              # checks running system
#   bash otest4.sh /mnt/target  # checks a chroot target
#
# Filesystem expectation: ext4 (decision 008 — btrfs dropped after the
# build15 unpackfs RAM freeze). §A FAILS on btrfs/@ leftovers on purpose.
# ============================================================================
set -u
R=$'\e[91m'; G=$'\e[92m'; Y=$'\e[93m'; C=$'\e[96m'; B=$'\e[1m'; X=$'\e[0m'
FAIL=0; RES=""
pass(){ echo "  $G ✓ OK: $X$1"; }
warn(){ echo "  $Y ⚠ $1$X"; }
fail(){ echo "  $R ✗ FAIL: $X$1"; FAIL=$((FAIL+1)); RES="$RES\n  ✗ $1"; }
h(){ echo ""; echo "$B=== $1 ===$X"; }

ROOT="${1:-/}"
R_ROOT="${ROOT%/}"
# helper to run paths with optional chroot
R(){ [ "$ROOT" = "/" ] && "$@" || chroot "$R_ROOT" "$@"; }

echo "$B  OintOS installer acceptance test (root=$ROOT)$X"

# ---------------------------------------------------------------------------
h "A. ext4 root, no btrfs leftovers (decision 008)"
echo "  -- root fstype --"
FS_TYPE=$(R findmnt -no FSTYPE / 2>/dev/null || echo "?")
echo "    root fstype: $FS_TYPE"
[ "$FS_TYPE" = "ext4" ] && pass "root is ext4" || fail "root is '$FS_TYPE' (expected ext4)"
echo "  -- no @ subvol dirs --"
for _d in "@" "@home" "@cache" "@log" "@swap"; do
    [ -e "${R_ROOT}/${_d}" ] && fail "btrfs leftover '/${_d}' present" || pass "no '/${_d}'"
done
echo "  -- fstab has no subvol= --"
R grep -q "subvol=" "${R_ROOT}/etc/fstab" 2>/dev/null && fail "fstab has subvol= (btrfs leftover)" || pass "fstab clean (no subvol=)"

# ---------------------------------------------------------------------------
h "B. Bootloader (GRUB + os-prober)"
[ -n "$(ls "${R_ROOT}/boot/grub" 2>/dev/null)" ] && pass "GRUB files present" || warn "no /boot/grub installed"
R command -v grub-install >/dev/null 2>&1 && pass "grub-install binary present" || warn "no grub-install"
R dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+os-prober" && pass "os-prober installed (dual-boot)" || warn "os-prober not present"
# UEFI check: /sys/firmware/efi exists only on UEFI boot (runtime check,
# not chrooted). The ESP mounts at /boot/efi, so its dir is /boot/efi/EFI
# — the old check looked at /EFI (filesystem root), which never exists.
if [ -d /sys/firmware/efi ]; then
    [ -d "${R_ROOT}/boot/efi/EFI" ] \
        && pass "UEFI boot + ESP mounted (/boot/efi/EFI)" \
        || fail "UEFI boot but no /boot/efi/EFI (ESP not mounted?)"
else
    warn "booted in BIOS mode (/sys/firmware/efi absent)"
fi
# update-grub output check (chroot only)
if [ "$ROOT" != "/" ]; then
    R update-grub >/dev/null 2>&1 && pass "update-grub runs" || warn "update-grub failed in target"
fi

# ---------------------------------------------------------------------------
h "C. User + sudo group"
U=$(R ls /home 2>/dev/null | grep -v '^lost+found$' | head -1)
echo "    home user: $U"
if [ -n "$U" ]; then
    R getent group sudo >/dev/null 2>&1 && R getent passwd "$U" >/dev/null 2>&1 && pass "user '$U' exists + sudo group present"
else
    warn "no regular user home found (may be a root-only test install)"
fi

# ---------------------------------------------------------------------------
h "D. No timeshift/btrfs tooling (decision 008: dropped)"
[ -d "${R_ROOT}/etc/timeshift" ] && fail "/etc/timeshift present (should be gone)" || pass "no /etc/timeshift"
R dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+timeshift" && fail "timeshift installed (should be gone)" || pass "no timeshift"
R dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+btrfs-progs" && fail "btrfs-progs installed (should be gone)" || pass "no btrfs-progs"

# ---------------------------------------------------------------------------
h "E. No snapd / APT-first"
R dpkg -l snapd 2>/dev/null | grep -q ^ii && fail "snapd present (should be absent)" || pass "no snapd"

# ---------------------------------------------------------------------------
h "F. No installer leftovers on installed system (build22)"
_LEFTOVER=0
for _f in usr/bin/ointos-installer-prompt \
         usr/share/applications/ointos-installer.desktop \
         usr/share/applications/calamares.desktop \
         etc/xdg/autostart/ointos-installer.desktop \
         etc/sudoers.d/ointos-installer \
         etc/calamares \
         usr/share/calamares; do
    if [ -e "${R_ROOT}/${_f}" ]; then fail "installer leftover '/${_f}' present"; _LEFTOVER=1; fi
done
[ "$_LEFTOVER" -eq 0 ] && pass "no installer leftovers"
if ls "${R_ROOT}"/usr/share/applications/*kubuntu*.desktop "${R_ROOT}"/usr/share/applications/*Kubuntu*.desktop "${R_ROOT}"/home/*/Desktop/Install*.desktop 2>/dev/null | grep -q .; then
    fail "kubuntu/installer .desktop leftovers present"
else
    pass "no kubuntu/installer .desktop leftovers"
fi
R dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+calamares" && fail "calamares package on target (should be purged)" || pass "no calamares package"

# ---------------------------------------------------------------------------
h "G. Installer artifacts"
[ -f "${R_ROOT}/etc/ointos-installed" ] && pass "/etc/ointos-installed marker present" || fail "no /etc/ointos-installed (both paths must write it)"
[ -f "${R_ROOT}/usr/local/bin/ointos-unattended-plan" ] && pass "unattended plan driver shipped in live image" || warn "no /usr/local/bin/ointos-unattended-plan (pre-Phase-7 ISO?)"

# ---------------------------------------------------------------------------
echo ""
echo "==========================================================================="
echo "  INSTALLER ACCEPTANCE  —  $FAIL failure(s)"
echo "==========================================================================="
[ "$FAIL" -eq 0 ] && echo "  $G All checks passed — install looks good.$X" || { echo "  $R $FAIL failure(s):$X"; echo -e "$RES"; }
echo "==========================================================================="
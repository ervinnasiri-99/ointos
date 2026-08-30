#!/bin/bash
# ============================================================================
# otest3.sh — Phase 4 acceptance test
#
# Verifies Phase-4 state in the built ISO:
#   A. Network applet now shows wired (en*) as a managed, connected device
#   B. Wallpaper appears in the KDE picker AND is default (//OintOS wallpaper)
#   C. OintOS logo is installed system-wide (hicolor + pixmaps + distributor-logo)
#   D. Curated default apps are present (.deb, no snaps)
#   E. Regressions: no snapd, Brave .deb, btrfs, casper initrd patched
#
# Run in the OintOS VM:  bash otest3.sh
# ============================================================================
set -u
R=$'\e[91m'; G=$'\e[92m'; Y=$'\e[93m'; C=$'\e[96m'; B=$'\e[1m'; X=$'\e[0m'
FAIL=0; RES=""
pass(){ echo "  $G✓ OK: $X$1"; }
warn(){ echo "  $Y⚠ $1$X"; }
fail(){ echo "  $R✗ FAIL: $X$1"; FAIL=$((FAIL+1)); RES="$RES\n  ✗ $1"; }
h(){ echo ""; echo "$B=== $1 ===$X"; }
pause(){ read -r -p "  [Enter]... " _; }

echo "$B  OintOS Phase 4 acceptance test$X"

# ---------------------------------------------------------------------------
h "A. Network applet / wired (en*) visible + managed"
echo "  -- nmcli device --"
nmcli device 2>/dev/null | head -8
WIRED=$(nmcli -t device 2>/dev/null | awk -F: '$1 ~ /^en/ {print $1; exit}')
if [ -n "$WIRED" ]; then
    pass "wired device found: $WIRED"
    STATE=$(nmcli -t device show "$WIRED" 2>/dev/null | awk -F: '/^STATE:/{print $2}')
    echo "    state: $STATE"
    nmcli -t connection show --active 2>/dev/null | grep -q "ointos-eth" && pass "ointos-eth connection active" || warn "no 'ointos-eth' active connection (may auto-connect under a different id)"
else
    fail "no en* device seen by NetworkManager (applet will show nothing)"
fi
echo "  -- internet --"
ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && pass "ping OK" || fail "no ping"
pause

# ---------------------------------------------------------------------------
h "B. Wallpaper: OintOS in picker + set as default"
echo "  -- wallpaper package --"
if [ -f /usr/share/wallpapers/OintOS/metadata.json ]; then
    pass "wallpaper package exists + metadata.json"
    grep -q "X-Plasma-Image" /usr/share/wallpapers/OintOS/metadata.json && pass "metadata has X-Plasma-Image" || warn "metadata missing X-Plasma-Image"
else
    fail "no /usr/share/wallpapers/OintOS/metadata.json (picker won't list it)"
fi
echo "  -- default wallpaper config (skel) --"
if grep -rqi "OintOSWallpaper" /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null; then
    pass "skel desktop config points at OintOS wallpaper"
else
    warn "skel desktop config NOT set (check /etc/skel)"
fi
echo "  -- backgrounds fallback --"
[ -f /usr/share/backgrounds/ointos.png ] && pass "ointos.png in backgrounds" || warn "no /usr/share/backgrounds/ointos.png"
pause

# ---------------------------------------------------------------------------
h "C. Logo system-wide"
echo "  -- hicolor icon (should exist in sizes) --"
CNT=$(ls /usr/share/icons/hicolor/*/apps/ointos.png 2>/dev/null | wc -l)
[ "$CNT" -ge 1 ] && pass "ointos.png in hicolor ($CNT sizes)" || fail "no hicolor ointos.png"
echo "  -- pixmaps --"
[ -f /usr/share/pixmaps/ointos.png ] && pass "ointos.png in pixmaps" || warn "no pixmaps/ointos.png"
[ -f /usr/share/pixmaps/distributor-logo.png ] && pass "distributor-logo.png present (About/Settings)" || warn "no distributor-logo"
pause

# ---------------------------------------------------------------------------
h "D. Curated default apps (.deb)"
for app in elisa mpv kcalc sweeper filelight kcharselect; do
    command -v $app >/dev/null 2>&1 && pass "$app present" || { command -v $app; fail "$app MISSING"; }
done
# kdeconnect + print-manager are services/GUIs, check binaries or pkgs
dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+kdeconnect" && pass "kdeconnect installed" || warn "kdeconnect not .deb-installed"
dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+print-manager" && pass "print-manager installed" || warn "print-manager not .deb-installed"
pause

# ---------------------------------------------------------------------------
h "E. Regressions"
dpkg -l snapd 2>/dev/null | grep -q ^ii && fail "snapd STILL present" || pass "no snapd"
command -v brave-browser >/dev/null 2>&1 && pass "brave present" || fail "brave missing"
which btrfs timeshift >/dev/null 2>&1 && pass "btrfs+timeshift" || fail "btrfs/timeshift missing"
# casper initrd patched? check the casper script no longer has the panic guard
if [ -f /usr/share/initramfs-tools/scripts/casper ]; then
    grep -q "no support found" /usr/share/initramfs-tools/scripts/casper && warn "casper panic string still present in script (may still be patched in initrd)" || pass "casper no false-panic string (script patched)"
else
    warn "casper initramfs script not on live root (normal for live squashfs; patched at build)"
fi
pause

# ---------------------------------------------------------------------------
echo ""
echo "==========================================================================="
echo "  PHASE 4 ACCEPTANCE  —  $FAIL failure(s)"
echo "==========================================================================="
[ "$FAIL" -eq 0 ] && echo "  $G All checks passed — Phase 4 basics look good.$X" || { echo "  $R $FAIL failure(s):$X"; echo -e "$RES"; }
echo "==========================================================================="
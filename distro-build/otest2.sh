#!/bin/bash
# ============================================================================
# otest2.sh — ACCEPTANCE test for OintOS build #2 (the fixed build)
#
# Verifies the fixes baked into this build actually work in the VM:
#   1. NO snapd / no snap (APT-first policy)
#   2. Brave browser installed as a real .deb (not the snap stub)
#   3. Network auto-connects (NM managed + systemd-networkd) — no manual fix
#   4. Audio CLI present (aplay) + PipeWire
#   5. General regressions from build #1 (btrfs, systemd, GPU, mounts)
#
# Run in the OintOS VM's Konsole:  bash otest2.sh
# ============================================================================
set -u
RED=$'\e[91m'; GRN=$'\e[92m'; YEL=$'\e[93m'; CYN=$'\e[96m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
FAIL=0; RESULTS=""
pass() { echo "  ${GRN}✓ OK:${RESET} $1"; }
warn() { echo "  ${YEL}⚠ ${1}${RESET}"; }
fail() { echo "  ${RED}✗ FAIL:${RESET} $1"; FAIL=$((FAIL+1)); RESULTS="$RESULTS\n  ✗ $1"; }
info() { echo "  ${CYN}· ${1}${RESET}"; }
h() { echo ""; echo "${BOLD}=== $1 ===${RESET}"; }
pause() { read -r -p "  [Enter] continue... " _; }

echo "${BOLD}  OintOS build #2 — acceptance test
  (checks the fixes from the rebuild actually work)${RESET}"

# ---------------------------------------------------------------------------
h "1. NO SNAPS (policy)"
if dpkg -l snapd 2>/dev/null | tail -1 | grep -q ^ii; then
    fail "snapd is STILL installed"
else
    pass "snapd is gone"
fi
if command -v snap >/dev/null 2>&1; then
    fail "snap binary still present"
else
    pass "no snap binary"
fi
if [ -x /usr/bin/firefox ] && ! snap list 2>/dev/null | grep -q firefox; then
    warn "firefox stub present (check it's not the snap shim)"
fi
pause

# ---------------------------------------------------------------------------
h "2. BRAVE browser (real .deb)"
if command -v brave-browser >/dev/null 2>&1; then
    pass "brave-browser found: $(readlink -f "$(command -v brave-browser)")"
    dpkg -l brave-browser 2>/dev/null | tail -1 | grep -q '^ii' && pass "brave-browser is a real .deb" || warn "brave .deb status?"
else
    fail "brave-browser NOT installed"
fi
# Confirm it's NOT a snap shim
if [ -e /usr/bin/brave-browser ] && grep -qi 'snap' /usr/bin/brave-browser 2>/dev/null; then
    fail "brave-browser looks like a snap shim!"
else
    pass "brave-browser is a native .deb (no snap shim)"
fi
echo "  launch test:"
timeout 8 brave-browser --version 2>&1 | head -1 && pass "brave --version worked" || warn "brave --version failed (may need display)"
pause

# ---------------------------------------------------------------------------
h "3. NETWORK auto-connect (should NOT need fix-network.sh)"
ETH=$(ip -4 addr show 2>/dev/null | awk '/^[0-9]+: /{gsub(/:/,"",$2); if($2!="lo") print $2}' | head -1)
if [ -n "$ETH" ]; then
    pass "ethernet interface: $ETH"
    ip -4 addr show "$ETH" 2>/dev/null | grep -q 'inet ' && pass "$ETH has IPv4 (auto-connected)" || fail "$ETH has NO IP (still needs manual fix)"
else
    fail "no ethernet interface found"
fi
ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && pass "ping 8.8.8.8 OK" || fail "no internet"
echo "  NetworkManager state:"
nmcli device 2>/dev/null | head -4 || echo "  (nmcli unavailable)"
pause

# ---------------------------------------------------------------------------
h "4. AUDIO tools"
command -v aplay >/dev/null 2>&1 && pass "aplay present" || fail "aplay missing (alsa-utils didn't install?)"
command -v pactl >/dev/null 2>&1 && pass "pactl (pipewire-pulse) present" || warn "pactl missing"
aplay -l 2>&1 | head -4
pause

# ---------------------------------------------------------------------------
h "5. REGRESSIONS: btrfs / systemd / GPU / mounts"
which btrfs timeshift >/dev/null 2>&1 && pass "btrfs + timeshift" || fail "btrfs/timeshift missing"
echo "  systemd: $(systemctl is-system-running 2>&1)"
[ "$(systemctl --failed --no-legend 2>/dev/null | wc -l)" -le 2 ] && pass "few failed units" || { warn "failed units:"; systemctl --failed --no-legend | head; }
for d in /proc /sys /dev; do mountpoint -q "$d" && pass "$d mounted" || fail "$d MISSING"; done
command -v inxi >/dev/null 2>&1 && inxi -Gzx 2>/dev/null | grep -E 'Device-1|OpenGL|Vulkan' | head -3
pause

# ---------------------------------------------------------------------------
h "6. KDE / desktop session"
echo "  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset}  SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
echo "  User: $(whoami 2>/dev/null)  (run as oinstaller for a real desktop check)"
groups 2>/dev/null | grep -q sudo && pass "user in sudo group" || warn "current user NOT in sudo group (run as oinstaller)"
pause

# ---------------------------------------------------------------------------
h "7. Journal errors worth noting"
journalctl -b -p err --no-pager 2>&1 | grep -vE 'vmw_msg_ioctl|Failed to open channel' | tail -15
pause

# ---------------------------------------------------------------------------
echo ""
echo "==========================================================================="
echo "  BUILD #2 ACCEPTANCE SUMMARY  —  $FAIL failure(s)"
echo "==========================================================================="
[ "$FAIL" -eq 0 ] && echo "  ${GRN}ALL fixes verified — build #2 looks good.${RESET}" \
    || { echo "  ${RED}$FAIL failure(s):${RESET}"; echo -e "$RESULTS"; }
echo "==========================================================================="
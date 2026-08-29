#!/bin/bash
# ============================================================================
# otest.sh — interactive OintOS live-session test harness
#
# Run in the OintOS VM's Konsole:  bash otest.sh
# Runs each test, waits for Enter between sections, collects a summary at the
# end so issues found here get baked into the next isobuild.sh.
# NO SNAPS — apt-only. If anything pulls a snap (e.g. 'firefox' on 26.04 is a
# snap transition package) it's flagged here so we can pick a real .deb
# browser instead.
# ============================================================================
set -u
RED=$'\e[91m'; GRN=$'\e[92m'; YEL=$'\e[93m'; CYN=$'\e[96m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
PAUSE="${1:-}"          # pass 'auto' to not wait between tests
RESULTS=""
FAIL=0

pass() { echo "  ${GRN}✓ OK:${RESET} $1"; }
warn() { echo "  ${YEL}⚠ ${1}${RESET}"; }
fail() { echo "  ${RED}✗ FAIL:${RESET} $1"; FAIL=$((FAIL+1)); RESULTS="$RESULTS\n  ✗ $1"; }
info() { echo "  ${CYN}· ${1}${RESET}"; }

pause() { [ "$PAUSE" = "auto" ] || { echo ""; read -r -p "  [Enter] continue... " _; }; }

header() { echo ""; echo "${BOLD}=== $1 ===${RESET}"; }

echo "${BOLD}
   ______________  OintOS live-session tests  ______________${RESET}"
echo "  Run each test; issues collected at the end for the next build."
echo ""

# ---------------------------------------------------------------------------
header "1. Snap / package-manager stance"
echo "  Detecting snapd / snap packages (we want NONE):"
dpkg -l snapd 2>/dev/null | tail -1 | grep -q ^ii && \
    warn "snapd is INSTALLED (should not be, for a snap-free build)" || \
    pass "no snapd installed"
if command -v snap >/dev/null 2>&1; then
    snap list 2>/dev/null | head -5
    warn "snap binary present — OintOS is APT-first, snap should be absent"
else
    pass "no snap binary"
fi
pause

# ---------------------------------------------------------------------------
header "2. Networking (is the NIC really up & managed?)"
ip -4 addr show | grep -E '^[0-9]+:|inet '
ETH=$(ip -4 addr show | awk '/^[0-9]+: /{gsub(/:/,"",$2); if($2 != "lo") print $2}')
[ -n "$ETH" ] && ip -4 addr show "$ETH" | grep -q 'inet ' && pass "interface $ETH has IPv4" || fail "no IPv4 on any interface"
ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && pass "ping 8.8.8.8" || fail "no internet ping"
getent hosts archive.ubuntu.com >/dev/null 2>&1 && pass "DNS resolves" || fail "DNS broken"
nmcli device 2>/dev/null | head -6
pause

# ---------------------------------------------------------------------------
header "3. Display / GPU (VirtualBox/other)"
inxi -Gzx 2>/dev/null | head -15 || { echo "  (inxi missing)"; ls /dev/dri 2>/dev/null || echo "  no /dev/dri"; }
echo "  XDG_SESSION_TYPE=$XDG_SESSION_TYPE  DISPLAY=$DISPLAY  WAYLAND=$WAYLAND_DISPLAY"
pause

# ---------------------------------------------------------------------------
header "4. Sound"
if command -v pactl >/dev/null 2>&1; then
    pactl info 2>&1 | grep -E 'Server Name|Default Sink' | head -3 || warn "pulse/pipewire not reachable"
else
    warn "pactl missing"
fi
aplay -l 2>&1 | head -6
pause

# ---------------------------------------------------------------------------
header "5. Filesystem / Btrfs tooling"
which btrfs timeshift 2>/dev/null && pass "btrfs+timeshift present" || fail "btrfs/timeshift missing"
sudo btrfs --version 2>/dev/null
echo "  mount root: $(findmnt -no FSTYPE / 2>/dev/null || echo '?')"
pause

# ---------------------------------------------------------------------------
header "6. Systemd health"
echo "  is-system-running:"; systemctl is-system-running 2>&1
echo "  failed units:"; systemctl --failed --no-legend 2>&1 | head -15
[ "$(systemctl --failed --no-legend 2>/dev/null | wc -l)" -le 2 ] && pass "few failed units" || warn "failed units above"
pause

# ---------------------------------------------------------------------------
header "7. Apt works (APT-first, no snap)"
sudo apt-get update 2>&1 | tail -2
echo "  testing install of a real .deb (curl):"
if sudo apt-get install -y --no-install-recommends curl 2>&1 | tail -2 | grep -qE "^Setting up curl|already the newest"; then
    pass "apt install works"
else
    warn "apt install output above — check"
fi
pause

# ---------------------------------------------------------------------------
header "8. User / sudo"
id
sudo -n true 2>/dev/null && pass "passwordless sudo" || warn "sudo requires password (OintOS sets NOPASSWD)"

echo ""
echo "  Testing if default user is in sudo group:"
groups | grep -q sudo && pass "user in sudo group" || warn "user NOT in sudo group"

# ---------------------------------------------------------------------------
header "9. Browser (we need a real .deb browser, NOT snap firefox)"
echo "  Checking for a usable browser:"
for b in firefox firefox-esr chromium chromium-browser falkon epiphany-browser; do
    command -v $b >/dev/null 2>&1 && echo "  found: $b ($(readlink -f $(command -v $b)))"
done
dpkg -l | grep -iE 'firefox|chromium|falkon|epiphany' | awk '{print $2}' | head
echo "  NOTE: on Ubuntu 26.04, 'firefox' is a snap-transition stub. We want a real .deb browser."
pause

# ---------------------------------------------------------------------------
header "10. Kernel / boot"
uname -r
echo "  loaded modules of interest:"
lsmod | grep -E 'virtio|vbox|e1000|8139|amdgpu|nouveau|nvidia|i915' | head
pause

# ---------------------------------------------------------------------------
header "11. /dev /proc /sys mount points exist (panic regression)"
for d in /proc /sys /dev; do
    [ -d "$d" ] && mountpoint -q "$d" && pass "$d mounted" || fail "$d not mounted"
done
pause

# ---------------------------------------------------------------------------
header "12. Journal errors (the ones that matter)"
journalctl -b -p err --no-pager 2>&1 | tail -20
pause

# ---------------------------------------------------------------------------
echo ""
echo "==========================================================================="
echo "  RESULT SUMMARY  —  failures to bake into isobuild.sh:"
echo "==========================================================================="
if [ "$FAIL" -eq 0 ]; then
    echo "  ${GRN}All checks passed (no failures).${RESET}"
else
    echo "  ${RED}$FAIL check(s) failed:${RESET}"
    echo -e "$RESULTS"
fi
echo ""
echo "  To contribute: paste this output — fixes go into distro-build/isobuild.sh"
echo "==========================================================================="
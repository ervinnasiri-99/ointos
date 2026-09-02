#!/bin/bash
# ============================================================================
# ocal.sh — Calamares diagnostic + auto-fix for OintOS live session
#
# Run in the OintOS VM:  bash ocal.sh
#
# Diagnoses Calamares branding/config issues and offers to fix them.
# ============================================================================
set -u
RED=$'\e[91m'; GRN=$'\e[92m'; YEL=$'\e[93m'; CYN=$'\e[96m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
pass() { echo "  $GRN✓ OK:$RESET $1"; }
warn() { echo "  $YEL⚠ $1$RESET"; }
fail() { echo "  $RED✗ FAIL:$RESET $1"; }
h() { echo ""; echo "$BOLD=== $1 ===$RESET"; }

echo "${BOLD}OintOS Calamares Diagnostic${RESET}"
echo ""

h "1. Branding.desc contents"
DESC="/etc/calamares/branding/ointos/branding.desc"
if [ -f "$DESC" ]; then
    echo "  File exists: $DESC"
    echo "  Full contents:"
    cat "$DESC"
    echo ""
    echo "  --- YAML validity ---"
    python3 -c "import yaml; yaml.safe_load(open('$DESC')); print('YAML VALID')" 2>&1 || warn "YAML parsing issue"
    echo "  --- Keys present ---"
    grep -E '^[a-zA-Z].*:' "$DESC" | head -15
    echo "  --- 'style' key check ---"
    grep -q '^style:' "$DESC" && warn "'style' key found (may cause YAML map error)" || pass "no 'style' key"
else
    fail "branding.desc NOT FOUND at $DESC"
fi

h "2. Branding image paths"
for p in /etc/calamares/branding/ointos/img/logo.png /usr/share/calamares/branding/ointos/img/logo.png; do
    [ -f "$p" ] && pass "$p exists" || warn "$p missing"
done

h "3. Calamares modules & QML"
ls -d /usr/lib/x86_64-linux-gnu/calamares/modules/ 2>/dev/null && pass "C++ modules at /usr/lib/..." || warn "C++ modules not found"
ls -d /usr/share/calamares/modules/ 2>/dev/null && pass "modules symlink exists" || warn "no /usr/share/calamares/modules/ symlink"
ls -d /usr/share/calamares/qml/ 2>/dev/null && pass "QML directory exists" || warn "no QML dir"
ls -d /etc/calamares/qml/ 2>/dev/null && pass "QML symlink exists" || warn "no /etc/calamares/qml/ symlink"

h "4. settings.conf"
if [ -f /etc/calamares/settings.conf ]; then
    echo "  Contents:"
    cat /etc/calamares/settings.conf
else
    warn "settings.conf not found"
fi

h "5. Wallpaper"
CFG="/home/oinstaller/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$CFG" ]; then
    grep -A2 "Wallpaper" "$CFG" | head -5
    grep -q "OintOS" "$CFG" && pass "OintOS wallpaper in config" || warn "OintOS wallpaper NOT in config"
else
    warn "plasma config not found"
fi

h "6. Systemd wallpaper service"
systemctl --user status ointos-wallpaper.service 2>&1 | head -5 || warn "service not found"
ls -la /etc/systemd/user/graphical-session.target.wants/ointos-wallpaper.service 2>/dev/null \
    && pass "service enabled system-wide" || warn "service not enabled system-wide"

h "7. Snap check"
dpkg -l snapd 2>/dev/null | grep -q ^ii && fail "snapd STILL installed" || pass "no snapd"

h "8. Network"
nmcli device 2>/dev/null | head -5

h "9. Recommended fixes"
echo "  To fix branding.desc (invalid 'style' key):"
echo "    sudo sed -i '/^style:/d' $DESC"
echo "  To fix branding.desc (invalid 'images' key — shadow default):"
echo "    sudo sed -i '/^images:/d' $DESC"
echo "  To fix networking (manual override):"
echo "    sudo nmcli device set enp0s3 managed yes && sudo systemctl restart NetworkManager"
echo ""
echo "  Or for a full rebuild with all fixes:"
echo "    cd ~/ointos && git pull --ff-only && cd distro-build && sudo bash dockerbuild.sh"
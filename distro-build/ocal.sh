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
    echo "  --- 'style' key check (must be a MAP, not a string) ---"
    python3 -c "import yaml; d=yaml.safe_load(open('$DESC')); assert isinstance(d.get('style'), dict), 'style not a MAP'; print('style MAP OK')" 2>&1 || fail "'style' missing or not a YAML map"
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

h "4. settings.conf + module configs"
if [ -f /etc/calamares/settings.conf ]; then
    grep -q 'modules-search' /etc/calamares/settings.conf \
        && pass "modules-search present (missing = ALL modules fail)" \
        || fail "modules-search MISSING — every module fails to load"
    echo "  Contents:"
    cat /etc/calamares/settings.conf
else
    fail "settings.conf not found"
fi
if grep -q 'partitionLayout' /etc/calamares/modules/partition.conf 2>/dev/null \
    && grep -q 'mountPoint.*"/"' /etc/calamares/modules/partition.conf 2>/dev/null; then
    pass "partitionLayout present (explicit root)"
else
    fail "partitionLayout MISSING or no / entry — erase emits ESP-only (build19)"
fi
if grep -q 'shellprocess@rootcheck' /etc/calamares/settings.conf 2>/dev/null \
    && [ -f /etc/calamares/modules/shellprocess_rootcheck.conf ]; then
    pass "rootcheck guard wired (shellprocess@rootcheck)"
else
    fail "rootcheck guard NOT wired"
fi
echo "  --- /etc/calamares/modules/ (Calamares ONLY looks here + /usr/share/.../modules) ---"
ls /etc/calamares/modules/ 2>/dev/null || fail "modules/ dir missing"
for _m in welcome locale keyboard partition users summary mount unpackfs displaymanager bootloader shellprocess shellprocess_rootcheck finished machineid fstab localecfg networkcfg hwclock grubcfg umount locale keyboard; do
    [ -f "/etc/calamares/modules/$_m.conf" ] || [ -f "/usr/share/calamares/modules/$_m.conf" ] \
        && pass "$_m.conf found" || warn "$_m.conf missing (OK only for summary/finished + job modules needing no conf)"
done

h "4b. Live entries: OintOS only (build22 gate)"
if ls /usr/share/applications/*kubuntu*.desktop /usr/share/applications/*Kubuntu*.desktop /usr/share/applications/calamares.desktop /etc/xdg/autostart/*calamares*.desktop /etc/xdg/autostart/*kubuntu*.desktop 2>/dev/null | grep -q .; then
    fail "kubuntu/calamares installer entries present in live session"
else
    pass "live session has OintOS installer only"
fi
file /usr/share/calamares/branding/ointos/img/logo.png /etc/calamares/branding/ointos/img/logo.png 2>/dev/null | grep -qi 'rgba\|alpha' \
    && pass "installer logo has transparency (RGBA)" \
    || fail "installer logo NOT transparent (opaque PNG)"

h "5. Wallpaper"
CFG="/home/oinstaller/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$CFG" ]; then
    grep -A2 "Wallpaper" "$CFG" | head -5
    grep -q "OintOS" "$CFG" && pass "OintOS wallpaper in config" || warn "OintOS wallpaper NOT in config"
else
    warn "plasma config not found"
fi

h "5b. Wallpaper defaults for installed user (017/018)"
grep -q "OintOS" /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null \
    && pass "/etc/skel seeds desktop wallpaper" \
    || fail "/etc/skel missing wallpaper (installed user gets default breeze)"
grep -q "OintOSWallpaper" /etc/skel/.config/kscreenlockerrc 2>/dev/null \
    && pass "/etc/skel seeds lock-screen wallpaper" \
    || fail "/etc/skel missing kscreenlockerrc"
grep -qE "^background=.*OintOSWallpaper" /usr/share/sddm/themes/breeze/theme.conf.user 2>/dev/null \
    && grep -q "^type=image" /usr/share/sddm/themes/breeze/theme.conf.user 2>/dev/null \
    && pass "SDDM breeze login wallpaper set" \
    || fail "SDDM theme.conf.user missing/wrong (login screen not branded)"

h "6. Systemd wallpaper service"
systemctl --user status ointos-wallpaper.service 2>&1 | head -5 || warn "service not found"
ls -la /etc/systemd/user/graphical-session.target.wants/ointos-wallpaper.service 2>/dev/null \
    && pass "service enabled system-wide" || warn "service not enabled system-wide"

h "6b. Unattended plan driver (019/020)"
[ -x /usr/local/bin/ointos-unattended-plan ] \
    && pass "ointos-unattended-plan shipped" \
    || fail "plan driver missing from live image"
[ -f /usr/share/doc/ointos/example-plan-v3.json ] \
    && pass "example-plan-v3.json shipped" \
    || warn "no example v3 plan (pre-019 ISO?)"
python3 -c "import platform; ids={platform.freedesktop_os_release()['ID']}|set(platform.freedesktop_os_release().get('ID_LIKE','').split()); assert 'debian' in ids" 2>/dev/null \
    && pass "os-release ID_LIKE carries debian (apport safe)" \
    || fail "ID_LIKE lacks debian (apport crashes hide tracebacks)"

h "7. Snap check"
dpkg -l snapd 2>/dev/null | grep -q ^ii && fail "snapd STILL installed" || pass "no snapd"

h "8. Network"
nmcli device 2>/dev/null | head -5

h "9. Manual launch (passwordless calamares sudo on new builds)"
echo "  /usr/bin/ointos-installer-prompt"
echo "  (old builds need password 'ointos' when sudo prompts)"
echo ""
echo "  To fix networking (manual override):"
echo "    sudo nmcli device set enp0s3 managed yes && sudo systemctl restart NetworkManager"
echo ""
echo "  NOTE: branding.desc 'style:' + 'images:' are CORRECT as YAML maps"
echo "  on current builds — do NOT delete them (that advice was for old ISOs)."
echo ""
echo "  Or for a full rebuild with all fixes:"
echo "    cd ~/ointos && git pull --ff-only && cd distro-build && sudo bash dockerbuild.sh"
#!/bin/bash
# ============================================================================
# collect-install-logs.sh — installer debug log toplayıcı (OintOS live VM).
#
#   bash collect-install-logs.sh
#
# Installer'ı debug modda açar. Kurulumu dene, hata alınca pencereyi kapat.
# Kapanınca ön/son sistem durumu + rsync/mount/ERROR satırları + session.log
# hepsini ~/calamares-logs-<tarih>.txt dosyasına yazar. O dosyayı yapıştır.
# ============================================================================
set -u
OUT=~/calamares-logs-$(date +%Y%m%d-%H%M).txt
CALLOG=/tmp/cal-debug.log

{
    echo "===== PRE: $(date) ====="
    echo "--- free ---"; free -h
    echo "--- lsblk ---"; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT; lsblk -f
    echo "--- df (full) ---"; df -h
    echo "--- swapon ---"; swapon --show 2>/dev/null || echo none
    echo "--- efi ---"; ls /sys/firmware/efi 2>&1
    echo "--- calamares mounts ---"; mount | grep -i calamares || echo none
    echo "--- cow/overlay ---"; mount | grep -E 'cow|overlay' || echo none
    echo "--- findmnt ---"; findmnt | grep -E 'calamares|cow|overlay|/dev/sd' || echo none
    echo "--- calamares-root size ---"; du -sh /tmp/calamares-root-* 2>&1
    echo "--- cmdline ---"; cat /proc/cmdline
    echo "--- modules-search ---"; grep -H 'modules-search' /etc/calamares/settings.conf
    echo "--- modules dir ---"; ls /etc/calamares/modules/
} > "$OUT" 2>&1

echo "Installer aciliyor. Kurulumu dene, hata alinca pencereyi kapat."
rm -f "$CALLOG"
SUDO_ENV=()
for _v in DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR QT_QPA_PLATFORMTHEME XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS; do
    [ -n "${!_v:-}" ] && SUDO_ENV+=("$_v=${!_v}")
done
# shellcheck disable=SC2086
sudo -E env "${SUDO_ENV[@]}" calamares -c /etc/calamares -d 2>&1 | tee "$CALLOG" | tail -3

{
    echo ""
    echo "===== POST: $(date) ====="
    echo "--- free ---"; free -h
    echo "--- df (full) ---"; df -h
    echo "--- swapon ---"; swapon --show 2>/dev/null || echo none
    echo "--- lsblk ---"; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
    echo "--- calamares mounts ---"; mount | grep -i calamares || echo none
    echo "--- findmnt ---"; findmnt | grep -E 'calamares|cow|overlay|/dev/sd' || echo none
    echo "--- calamares-root size ---"; du -sh /tmp/calamares-root-* 2>&1
    echo "--- dmesg ---"; dmesg | grep -i -E "squashfs|I/O error|read error|No space" | tail -15
    echo "--- rsync ---"; grep -n -i -A3 rsync "$CALLOG" | tail -20
    echo "--- mount/partition/ERROR ---"; grep -n -i -E "mount|no space|write failed|ERROR|calamares-root|Failed" "$CALLOG" | head -60
    echo "--- session.log root ---"; tail -50 /root/.cache/calamares/session.log 2>/dev/null || echo none
    echo "--- session.log user ---"; tail -50 ~/.cache/calamares/session.log 2>/dev/null || echo none
    echo "--- cal-debug tail ---"; tail -100 "$CALLOG"
} >> "$OUT" 2>&1

echo "Bitti: $OUT"
ls -la "$OUT"

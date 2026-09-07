#!/bin/bash
# ============================================================================
# install-watchdog.sh — freeze-proof install monitor (OintOS live VM).
#
# Writes to a SECOND virtual disk so a hard freeze + power-off keeps evidence.
# No guest additions needed: the VDI is read back on the host afterwards.
#
# ONE-TIME host setup (VirtualBox, VM powered off):
#   VBoxManage createhd --filename evidence.vdi --size 512 --format VDI
#   VBoxManage storageattach <vm> --storagectl SATA --port 1 --type hdd \
#       --medium evidence.vdi
#
# In the live VM, BEFORE starting the installer:
#   sudo mkfs.ext4 -F /dev/sdb && sudo mkdir -p /mnt/evidence \
#       && sudo mount /dev/sdb /mnt/evidence && sudo chmod 777 /mnt/evidence
#   CALLOG=/tmp/cal-debug.log nohup bash install-watchdog.sh >/dev/null 2>&1 &
#   bash collect-install-logs.sh   # installer runs in foreground
#
# After power-off: attach evidence.vdi to any Linux VM (or 7-Zip on Windows)
# and read watch.log. Post that file here.
# ============================================================================
set -u
EVDIR="${EVDIR:-/mnt/evidence}"
CALLOG="${CALLOG:-/tmp/cal-debug.log}"
LOG="$EVDIR/watch.log"

[ -d "$EVDIR" ] || { echo "ERROR: $EVDIR not mounted. See header." >&2; exit 1; }

echo "watchdog -> $LOG (every 30s, sync after each round)"
while true; do
    {
        echo "===== $(date) ====="
        echo "--- free ---"; free -h
        echo "--- df ---"; df -h
        echo "--- swapon ---"; swapon --show 2>/dev/null || echo none
        echo "--- calamares mounts ---"; mount | grep -i calamares || echo none
        echo "--- cow/overlay ---"; mount | grep -E 'cow|overlay' || echo none
        echo "--- findmnt ---"; findmnt | grep -E 'calamares|cow|overlay|/dev/sd' || echo none
        echo "--- calamares-root size ---"; du -sh /tmp/calamares-root-* 2>&1
        echo "--- cal-debug tail ---"; tail -15 "$CALLOG" 2>/dev/null || echo no-log-yet
    } >> "$LOG" 2>&1
    sync
    sleep 30
done

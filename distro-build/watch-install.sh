#!/bin/bash
# ============================================================================
# watch-install.sh — tek komutluk freeze-proof kurulum izleyici (OintOS live).
#
#   curl -fsSL https://raw.githubusercontent.com/ervinnasiri-99/ointos/main/distro-build/watch-install.sh | bash
#
# Yaptıkları sırayla:
#   1. /dev/sdb'yi evidence diski olarak hazırlar (mkfs + /mnt/evidence mount).
#      DİKKAT: /dev/sdb'nin evidence VDI'n olduğundan emin ol (lsblk ile bak).
#   2. install-watchdog.sh + collect-install-logs.sh'i GitHub'dan indirir,
#      watchdog'u arka planda başlatır (30sn'de bir /mnt/evidence/watch.log).
#   3. Installer'ı debug modda ÖNDE açar. Kurulumu dene, bitince/hata alınca
#      pencereyi kapat → loglar ~/calamares-logs-*.txt + watch.log'a düşer.
#
# Donarsa: power-off → evidence.vdi'yi host'ta aç → watch.log'u yapıştır.
# ============================================================================
set -u
BASE="https://raw.githubusercontent.com/ervinnasiri-99/ointos/main/distro-build"
EVDEV="${EVDEV:-/dev/sdb}"

echo "--- lsblk (EVDEV=$EVDEV oldugunu dogrula) ---"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$EVDEV" || { echo "ERROR: $EVDEV yok"; exit 1; }

echo "--- evidence diski hazirlaniyor ---"
sudo mkfs.ext4 -F "$EVDEV" >/dev/null 2>&1
sudo mkdir -p /mnt/evidence
sudo mount "$EVDEV" /mnt/evidence
sudo chmod 777 /mnt/evidence

echo "--- scriptler indiriliyor ---"
cd /tmp
curl -fsSL "$BASE/install-watchdog.sh" -o install-watchdog.sh
curl -fsSL "$BASE/collect-install-logs.sh" -o collect-install-logs.sh
chmod +x install-watchdog.sh collect-install-logs.sh

echo "--- watchdog baslatildi (-> /mnt/evidence/watch.log) ---"
CALLOG=/tmp/cal-debug.log nohup bash /tmp/install-watchdog.sh >/dev/null 2>&1 &
sleep 1
tail -2 /mnt/evidence/watch.log 2>/dev/null || echo "(ilk tur henuz yazilmadi)"

echo "--- installer aciliyor ---"
bash /tmp/collect-install-logs.sh

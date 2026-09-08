#!/bin/bash
# ============================================================================
# ointos-test.sh — OintOS live VM tam otomatik kurulum testi (tek komut).
#
#   curl -fsSL https://raw.githubusercontent.com/ervinnasiri-99/ointos/main/distro-build/ointos-test.sh | bash
#
# Sırayla:
#   0. ocal.sh'i indirip CALAMAGIC KAPI KONTROLÜ yapar: partitionLayout +
#      rootcheck wiring pass vermezse DURUR (yanlış ISO ile 2 saat yanmasın).
#   1. Evidence VDI'yi hazırlar (/dev/sdb varsayılan, EVDEV ile değişir).
#   2. Stale swap'i kapatır (önceki testin sda2'si erase'i bloklamasın).
#   3. Hedef diski TEMİZLER (/dev/sda varsayılan, TARGET ile değişir):
#      swapoff + umount (busy'nin ilacı: önce tutan şeyi bırak) + wipefs.
#   4. install-watchdog.sh + collect-install-logs.sh'i indirir, watchdog'u
#      başlatır (30sn'de bir /mnt/evidence/watch.log).
#   5. Installer'ı debug modda ÖNDE açar. Erase seç, kur, bitince pencereyi
#      kapat → loglar ~/ + /mnt/evidence'e düşer.
#
# Donarsa: power-off → evidence.vdi'yi host'ta aç → watch.log'u yapıştır.
# ============================================================================
set -u
BASE="https://raw.githubusercontent.com/ervinnasiri-99/ointos/main/distro-build"
EVDEV="${EVDEV:-/dev/sdb}"
TARGET="${TARGET:-/dev/sda}"

echo "=== [0/5] ISO kapı kontrolü (ocal.sh) ==="
cd /tmp
curl -fsSL "$BASE/ocal.sh" -o ocal.sh
bash ocal.sh > /tmp/ocal-out.txt 2>&1; OCAL_RC=$?
grep -E "partitionLayout|rootcheck guard" /tmp/ocal-out.txt || tail -5 /tmp/ocal-out.txt
if [ "$OCAL_RC" -ne 0 ] \
    || ! grep -q "partitionLayout present" /tmp/ocal-out.txt \
    || ! grep -q "rootcheck guard wired" /tmp/ocal-out.txt; then
    echo "DUR: bu ISO'da partitionLayout/rootcheck yok (build20+ ISO gerek)."
    echo "Full ocal çıktısı: /tmp/ocal-out.txt"
    exit 1
fi
echo "Kapı geçildi: partitionLayout + rootcheck var."

echo "=== [1/5] evidence diski ($EVDEV) hazırlanıyor ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$EVDEV" || { echo "ERROR: $EVDEV yok"; exit 1; }
# mkfs öncesi automount'u bırak (yoksa RO remount + boş watch.log).
sudo umount "$EVDEV" 2>/dev/null || true
sudo umount /run/media/oinstaller/* 2>/dev/null || true
sudo mkfs.ext4 -F "$EVDEV" >/dev/null 2>&1
sudo mkdir -p /mnt/evidence
sudo mount "$EVDEV" /mnt/evidence
sudo umount /run/media/oinstaller/* 2>/dev/null || true
sudo mount -o remount,rw /mnt/evidence 2>/dev/null || true
sudo chmod 777 /mnt/evidence
touch /mnt/evidence/.writetest && rm /mnt/evidence/.writetest \
    || { echo "ERROR: /mnt/evidence yazılamıyor"; exit 1; }
echo "evidence yazılabilir: OK"

echo "=== [2/5] stale swap kapatılıyor ==="
sudo swapoff -a 2>/dev/null || true

echo "=== [3/5] hedef disk ($TARGET) temizleniyor ==="
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$TARGET" || { echo "ERROR: $TARGET yok"; exit 1; }
# busy'nin ilacı sıra: önce swapon/udev tutuşunu bırak, sonra umount, sonra wipe.
sudo swapoff "$TARGET"* 2>/dev/null || true
sudo swapoff -a 2>/dev/null || true
for _p in $(lsblk -rno MOUNTPOINT "$TARGET" 2>/dev/null | grep -v '^$'); do
    sudo umount -l "$_p" 2>/dev/null || true
done
sudo umount -l "$TARGET"* 2>/dev/null || true
sudo udevadm settle 2>/dev/null || true
sleep 2
sudo wipefs -a "$TARGET" || {
    echo "wipefs busy — tutan mount:"
    lsblk -o NAME,MOUNTPOINT "$TARGET"
    mount | grep -E "$TARGET" || true
    echo "Yukarıdaki mount'ları kapatıp tekrar dene, ya da TARGET=/dev/sdX ile doğru diski ver."
    exit 1
}
sudo dd if=/dev/zero of="$TARGET" bs=1M count=10 status=none 2>/dev/null || true
sudo partprobe "$TARGET" 2>/dev/null || true
echo "--- temizlik sonrası ---"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$TARGET"

echo "=== [4/5] watchdog başlatılıyor (-> /mnt/evidence/watch.log) ==="
curl -fsSL "$BASE/install-watchdog.sh" -o install-watchdog.sh
curl -fsSL "$BASE/collect-install-logs.sh" -o collect-install-logs.sh
chmod +x install-watchdog.sh collect-install-logs.sh
CALLOG=/tmp/cal-debug.log nohup bash /tmp/install-watchdog.sh >/dev/null 2>&1 &
sleep 1
tail -2 /mnt/evidence/watch.log 2>/dev/null || echo "(ilk tur henüz yazılmadı)"

echo "=== [5/5] installer açılıyor ==="
bash /tmp/collect-install-logs.sh

#!/usr/bin/env bash
# Wipe the Samsung 980 PRO (old Omarchy install) and set it up as /mnt/games.
set -euo pipefail

DEV=/dev/nvme1n1
PART=${DEV}p1
MNT=/mnt/games
USER_NAME=${SUDO_USER:?Run with sudo from your normal user: sudo ./games-drive.sh}

# --- Guards: only ever touch the Samsung 980 PRO, never the system drive ----
model=$(cat /sys/block/nvme1n1/device/model | xargs)
[[ $model == "Samsung SSD 980 PRO 500GB" ]] || { echo "Unexpected model on $DEV: $model" >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -qE '^(/|/home|/boot)$'; then
    echo "$DEV holds a system mount; refusing" >&2; exit 1
fi

echo "==> Unmounting and locking the old encrypted volume"
for mp in $(lsblk -nro MOUNTPOINTS "$DEV" | grep -v '^$'); do umount "$mp"; done
for m in $(lsblk -nro NAME,TYPE "$DEV" | awk '$2=="crypt"{print $1}'); do cryptsetup close "$m"; done

echo "==> Wiping $DEV"
wipefs -a "${DEV}p1" "${DEV}p2" 2>/dev/null || true
wipefs -a "$DEV"

echo "==> New GPT with one Linux partition"
printf 'label: gpt\n,,L\n' | sfdisk -q "$DEV"
udevadm settle

echo "==> Formatting btrfs, label 'games'"
mkfs.btrfs -q -f -L games "$PART"
udevadm settle

UUID=$(blkid -s UUID -o value "$PART")
echo "==> fstab: UUID=$UUID -> $MNT"
cp -n /etc/fstab /etc/fstab.bak
sed -i -e '\|[[:space:]]/mnt/games[[:space:]]|d' -e '/^# Games drive/d' /etc/fstab
cat >> /etc/fstab <<EOF

# Games drive (Samsung 980 PRO). nofail: boot continues if the drive is missing.
UUID=$UUID	/mnt/games	btrfs	rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,nofail,x-systemd.device-timeout=10s,x-gvfs-show,x-gvfs-name=Games	0 0
EOF

mkdir -p "$MNT"
systemctl daemon-reload
mount "$MNT"
mkdir -p "$MNT/SteamLibrary"
chown -R "$USER_NAME:$USER_NAME" "$MNT"

echo "==> Removing boot entries for systems that no longer exist"
# Limine/UEFI OS on the wiped drive, plus Windows/Fedora/Ubuntu whose partitions are gone
for id in 0000 0005 0002 0001 0004; do
    efibootmgr -q -b "$id" -B 2>/dev/null && echo "   removed Boot$id" || true
done

echo "==> Done"
findmnt "$MNT"
df -h "$MNT"
efibootmgr | head -6

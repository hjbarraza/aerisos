#!/bin/bash
set -e
# Merged T2 fix. Run from the Arch live ISO.
# Covers: mact2 repo, t2 kernel, apple-bce (builtin), wifi firmware,
# bootloader entry with real UUID/subvol, guarded reboot.
# Usage: bash t2.sh [root-dev] [efi-dev]

R=${1:-/dev/nvme0n1p2}
E=${2:-/dev/nvme0n1p1}
P="intel_iommu=on iommu=pt pcie_ports=compat"

mountpoint -q /mnt || { mount -o subvol=@ $R /mnt 2>/dev/null || mount $R /mnt; }
mountpoint -q /mnt/boot || mount $E /mnt/boot

# arch-mact2 repo in the target, written explicitly (idempotent)
grep -q '^\[arch-mact2\]' /mnt/etc/pacman.conf || \
  printf '\n[arch-mact2]\nServer = https://mirror.funami.tech/arch-mact2/os/x86_64\nSigLevel = Never\n' >> /mnt/etc/pacman.conf

# kernel + audio + microcode; wifi firmware installed into the target via chroot
pacstrap /mnt linux-t2 linux-t2-headers apple-t2-audio-config intel-ucode
arch-chroot /mnt pacman -Sy --noconfirm apple-bcm-firmware || \
  echo "WARN: apple-bcm-firmware failed, run t2wifi.sh from the installed system"

# apple-bce is builtin in linux-t2; drop the stray MODULES line from earlier runs
sed -i '/^MODULES=(apple-bce)/d' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux-t2

# bootloader entry from real UUID + btrfs subvol; ucode initrd only if present
U=$(blkid -s UUID -o value $R)
S=$(findmnt -no FSROOT /mnt)
F=""
[ "$S" != "/" ] && F="rootflags=subvol=${S#/}"
UC=""
[ -f /mnt/boot/intel-ucode.img ] && UC="initrd /intel-ucode.img"
cat > /mnt/boot/loader/entries/arch-t2.conf <<EOF
title Arch T2
linux /vmlinuz-linux-t2
$UC
initrd /initramfs-linux-t2.img
options root=UUID=$U $F rw $P
EOF
sed -i '/^$/d' /mnt/boot/loader/entries/arch-t2.conf
printf 'default arch-t2.conf\ntimeout 5\n' > /mnt/boot/loader/loader.conf

echo "=== bce check ==="
FOUND=$(find /mnt/usr/lib/modules -name '*bce*' 2>/dev/null; grep -l bce /mnt/usr/lib/modules/*t2*/modules.builtin 2>/dev/null || true)
echo "$FOUND"
cat /mnt/boot/loader/entries/arch-t2.conf
[ -n "$FOUND" ] || { echo "NO apple-bce in t2 kernel. Not rebooting. Photograph this."; exit 1; }

echo "=== reboot in 15s, Ctrl+C to stop ==="
sleep 15
cd /
umount -R /mnt
reboot

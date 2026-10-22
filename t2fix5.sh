#!/bin/bash
set -e
R=/dev/nvme0n1p2
E=/dev/nvme0n1p1
mountpoint -q /mnt || { mount -o subvol=@ $R /mnt 2>/dev/null || mount $R /mnt; }
mountpoint -q /mnt/boot || mount $E /mnt/boot
sed -i '/^MODULES=(apple-bce)/d' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux-t2
U=$(blkid -s UUID -o value $R)
S=$(findmnt -no FSROOT /mnt)
F=""
[ "$S" != "/" ] && F="rootflags=subvol=${S#/}"
cat > /mnt/boot/loader/entries/arch-t2.conf <<EOF
title Arch T2
linux /vmlinuz-linux-t2
initrd /intel-ucode.img
initrd /initramfs-linux-t2.img
options root=UUID=$U $F rw intel_iommu=on iommu=pt pcie_ports=compat
EOF
printf 'default arch-t2.conf\ntimeout 5\n' > /mnt/boot/loader/loader.conf
echo "=== bce check ==="
FOUND=$(find /mnt/usr/lib/modules -name '*bce*' 2>/dev/null; grep -l bce /mnt/usr/lib/modules/*t2*/modules.builtin 2>/dev/null || true)
echo "$FOUND"
cat /mnt/boot/loader/entries/arch-t2.conf
if [ -z "$FOUND" ]; then echo "NO apple-bce in t2 kernel. Not rebooting. Photograph this."; exit 1; fi
echo "=== reboot in 15s, Ctrl+C to stop ==="
sleep 15
cd /
umount -R /mnt
reboot

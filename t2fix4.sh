#!/bin/bash
set -e
R=/dev/nvme0n1p2
E=/dev/nvme0n1p1
P="intel_iommu=on iommu=pt pcie_ports=compat"
mountpoint -q /mnt || { mount -o subvol=@ $R /mnt 2>/dev/null || mount $R /mnt; }
mountpoint -q /mnt/boot || mount $E /mnt/boot
grep -q '^\[arch-mact2\]' /mnt/etc/pacman.conf || sed -n '/^\[arch-mact2\]/,/^$/p' /etc/pacman.conf >> /mnt/etc/pacman.conf
pacstrap /mnt linux-t2 linux-t2-headers apple-t2-audio-config
grep -q apple-bce /mnt/etc/mkinitcpio.conf || echo 'MODULES=(apple-bce)' >> /mnt/etc/mkinitcpio.conf
if [ -f /mnt/etc/kernel/cmdline ]; then
  grep -q pcie_ports /mnt/etc/kernel/cmdline || sed -i "1s/\$/ $P/" /mnt/etc/kernel/cmdline
fi
for f in /mnt/boot/loader/entries/*.conf; do
  [ -f "$f" ] || continue
  grep -q pcie_ports "$f" || sed -i "s/^options.*/& $P/" "$f"
done
arch-chroot /mnt mkinitcpio -P || true
grep -q '^default' /mnt/boot/loader/loader.conf && sed -i 's/^default.*/default *t2*/' /mnt/boot/loader/loader.conf || echo 'default *t2*' >> /mnt/boot/loader/loader.conf
echo "=== check ==="
ls /mnt/boot /mnt/boot/EFI/Linux /mnt/boot/loader/entries 2>/dev/null
echo "=== reboot in 15s, Ctrl+C to stop ==="
sleep 15
cd /
umount -R /mnt
reboot

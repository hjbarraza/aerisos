#!/bin/bash
set -e
lsblk -f
read -rp "Root partition (e.g. nvme0n1p5): " R </dev/tty
read -rp "EFI partition (e.g. nvme0n1p1): " E </dev/tty
mount -o subvol=@ /dev/$R /mnt 2>/dev/null || mount /dev/$R /mnt
mount /dev/$E /mnt/boot
sed -n '/^\[arch-mact2\]/,/^$/p' /etc/pacman.conf >> /mnt/etc/pacman.conf
pacstrap /mnt linux-t2 linux-t2-headers apple-t2-audio-config
echo 'MODULES=(apple-bce)' >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P
cd /mnt/boot/loader/entries
cp $(ls | grep -v fallback | head -1) t2.conf
sed -i 's/vmlinuz-linux/vmlinuz-linux-t2/;s/initramfs-linux.img/initramfs-linux-t2.img/;s/^title.*/title Arch T2/;s/^options.*/& intel_iommu=on iommu=pt pcie_ports=compat/' t2.conf
sed -i 's/^default.*/default t2.conf/' ../loader.conf
cd /
umount -R /mnt
reboot

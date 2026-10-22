#!/bin/bash
set -e
echo 'MODULES=(apple-bce)' >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P
cd /mnt/boot/loader/entries
cp $(ls | grep -v fallback | head -1) t2.conf
sed -i 's/vmlinuz-linux/vmlinuz-linux-t2/;s/initramfs-linux.img/initramfs-linux-t2.img/;s/^title.*/title Arch T2/;s/^options.*/& intel_iommu=on iommu=pt pcie_ports=compat/' t2.conf
sed -i 's/^default.*/default t2.conf/' ../loader.conf
cd /
umount -R /mnt
reboot

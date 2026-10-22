#!/bin/bash
set -e
grep -q '^\[arch-mact2\]' /etc/pacman.conf || printf '\n[arch-mact2]\nServer = https://mirror.funami.tech/arch-mact2/os/x86_64\nSigLevel = Never\n' >> /etc/pacman.conf
pacman -Sy --noconfirm linux-t2 linux-t2-headers apple-t2-audio-config
pacman -U --noconfirm https://mirror.funami.tech/arch-mact2/os/x86_64/apple-bcm-firmware-14.0-1-any.pkg.tar.zst
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&intel_iommu=on iommu=pt pcie_ports=compat /' /etc/default/grub
grep -q '^GRUB_DEFAULT=' /etc/default/grub && sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub || echo 'GRUB_DEFAULT=saved' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
grub-set-default "$(grep -m1 "menuentry 'Arch Linux, with Linux linux-t2'" /boot/grub/grub.cfg | sed "s/.*menuentry '\([^']*\)'.*/Advanced options for Arch Linux>\1/")"
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi_backend.conf
systemctl enable iwd NetworkManager
echo "=== check ==="
ls /boot | grep t2
grub-editenv list

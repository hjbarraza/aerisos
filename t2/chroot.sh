#!/bin/bash
set -e
# Run INSIDE the chroot of the installed system (or booted into it).
# Fixes mirrorlist, installs t2 kernel + wifi fetcher, writes boot entry.
# Does NOT reboot.

R=/dev/nvme0n1p2
E=/dev/nvme0n1p1
P="intel_iommu=on iommu=pt pcie_ports=compat"

mountpoint -q /boot || mount $E /boot

# official arch-mact2 mirrorlist (from arch-mact2-mirrorlist v3 package)
cat > /etc/pacman.d/arch-mact2-mirrorlist <<'EOF'
Server = https://arch-mact2.miningtcup.me/os/$arch
Server = https://mirror.funami.tech/arch-mact2/os/$arch
Server = https://mirror.syn-flut.de/arch-mact2/os/$arch
Server = https://t2mirror.01110011.eu.cc/arch-mact2/os/$arch
Server = https://arch-t2.slsrepo.com/
EOF
grep -q '^\[arch-mact2\]' /etc/pacman.conf || \
  printf '\n[arch-mact2]\nInclude = /etc/pacman.d/arch-mact2-mirrorlist\nSigLevel = Never\n' >> /etc/pacman.conf

# NOTE: the wifi package is apple-bcm-firmware-fetcher (apple-bcm-firmware does not exist)
pacman -Sy --noconfirm linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware-fetcher linux-firmware iwd

systemctl enable iwd || true
pacman -Q networkmanager >/dev/null 2>&1 && systemctl enable NetworkManager || true

# bootloader entry
if [ -d /boot/loader ]; then
  U=$(blkid -s UUID -o value $R)
  S=$(findmnt -no FSROOT / 2>/dev/null || echo /)
  F=""
  [ "$S" != "/" ] && F="rootflags=subvol=${S#/}"
  UC=""
  [ -f /boot/intel-ucode.img ] && UC="initrd /intel-ucode.img"
  cat > /boot/loader/entries/arch-t2.conf <<ENTRY
title Arch T2
linux /vmlinuz-linux-t2
$UC
initrd /initramfs-linux-t2.img
options root=UUID=$U $F rw $P
ENTRY
  sed -i '/^$/d' /boot/loader/entries/arch-t2.conf
  printf 'default arch-t2.conf\ntimeout 5\n' > /boot/loader/loader.conf
  echo "=== systemd-boot entry ==="
  cat /boot/loader/entries/arch-t2.conf
elif [ -d /boot/grub ]; then
  grep -q pcie_ports /etc/default/grub || \
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&$P /" /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
  echo "=== grub updated, pick the linux-t2 entry at boot ==="
else
  echo "WARN: no /boot/loader and no /boot/grub - bootloader not configured"
fi

echo "=== check ==="
ls /boot | grep -i t2 || { echo "NO t2 kernel in /boot. Do not reboot. Photograph this."; exit 1; }
echo "OK. Exit the chroot, then: umount -R /mnt ; reboot"

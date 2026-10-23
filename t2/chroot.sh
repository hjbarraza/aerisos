#!/bin/bash
set -e
# T2 Mac, MANUAL path only (stock Arch ISO + archinstall). The AerisOS T2 USB
# (iso/build.sh --t2) does all of this by itself; use that when you can.
#
# Run INSIDE the chroot of the fresh install (arch-chroot /mnt, with the EFI
# partition mounted at /mnt/boot), or booted into it. Adds the arch-mact2 repo,
# installs the t2 kernel + firmware fetcher, writes the default boot entry.
# Does NOT reboot.  Usage: bash chroot.sh [root-partition]

R=${1:-$(findmnt -no SOURCE / | sed 's/\[.*//')}
P="intel_iommu=on iommu=pt pcie_ports=compat modprobe.blacklist=t2bce_vhci"
# t2bce_vhci is blacklisted at boot and loaded 2 s later by a unit: linux-t2 7.2.x
# cold-boot panic "Fatal exception in interrupt" (t2linux/kernel#37)
install -Dm644 "$(dirname "$(readlink -f "$0")")/t2bce-vhci-late.service" /etc/systemd/system/t2bce-vhci-late.service
systemctl enable t2bce-vhci-late || true

mountpoint -q /boot || { echo "/boot is not mounted: mount the EFI partition at /mnt/boot before arch-chroot"; exit 1; }
[ -b "$R" ] || { echo "root partition '$R' not found; pass it: bash chroot.sh /dev/nvme0n1p2"; exit 1; }
echo "root: $R"

# official arch-mact2 mirrorlist (kept next to this script)
install -Dm644 "$(dirname "$(readlink -f "$0")")/arch-mact2-mirrorlist" /etc/pacman.d/arch-mact2-mirrorlist
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

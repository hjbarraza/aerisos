#!/bin/bash
[ "$EUID" -eq 0 ] || exec sudo bash "$0" "$@"
cp /etc/pacman.conf /etc/pacman.conf.bak
sed -i '/^\[arch-mact2\]/,/^$/d' /etc/pacman.conf
printf '\n[arch-mact2]\nServer = https://mirror.funami.tech/arch-mact2/os/x86_64\nSigLevel = Never\n' >> /etc/pacman.conf
echo "=== repo block ==="
grep -A3 '^\[arch-mact2\]' /etc/pacman.conf
if ! pacman -Sy --noconfirm apple-bcm-firmware; then
  curl -L -o /tmp/abf.pkg.tar.zst https://mirror.funami.tech/arch-mact2/os/x86_64/apple-bcm-firmware-14.0-1-any.pkg.tar.zst
  pacman -U --noconfirm /tmp/abf.pkg.tar.zst
fi
modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
modprobe brcmfmac
sleep 4
echo "=== wifi ==="
ip link | grep -i wlan || echo "no wlan device yet, reboot and rerun"
nmcli device wifi list || true

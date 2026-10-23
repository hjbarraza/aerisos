#!/bin/bash
# Repair a T2 Mac AerisOS install that no longer boots (kernel panic). Run from
# the live USB shell (as root), with Wi-Fi up:
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/repair.sh | bash
#
# Finds the install on the internal NVMe (1G vfat ESP + btrfs root with the
# archinstall or aeris-installer subvolumes), mounts it, and in a chroot
# reinstalls linux-t2 + headers, rebuilds the initramfs and refreshes
# systemd-boot. Does NOT reboot; it prints the boot entries at the end.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "Finding the install"
DISK=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1 ~ /nvme/ {print $1; exit}')
[[ -n $DISK ]] || { echo "no internal NVMe disk visible"; lsblk -f; exit 1; }
ROOT=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2=="btrfs"{print $1; exit}')
ESP=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2=="vfat"{print $1; exit}')
[[ -b $ROOT && -b $ESP ]] || { echo "need one btrfs and one vfat partition on $DISK"; lsblk -f "$DISK"; exit 1; }
echo "disk $DISK   root $ROOT   esp $ESP"

say "Mounting"
umount -R /mnt 2>/dev/null || true
mount "$ROOT" /mnt
SUBS=$(btrfs subvolume list /mnt | awk '{print $NF}')
# the system root is the subvolume that holds /etc and /usr
ROOTSUB=""
for s in $SUBS; do [[ -d /mnt/$s/etc && -d /mnt/$s/usr ]] && { ROOTSUB=$s; break; }; done
umount /mnt
[[ -n $ROOTSUB ]] || { echo "no subvolume with /etc and /usr among: $SUBS"; exit 1; }
echo "root subvolume: $ROOTSUB   (all: $(echo $SUBS))"
O=compress=zstd,noatime
mount -o "subvol=$ROOTSUB,$O" "$ROOT" /mnt
for s in $SUBS; do
    case $s in
        "$ROOTSUB") ;;
        @home|home)   mount -o "subvol=$s,$O" "$ROOT" /mnt/home ;;
        @log|log)     mount -o "subvol=$s,$O" "$ROOT" /mnt/var/log ;;
        @pkg|pkg)     mount -o "subvol=$s,$O" "$ROOT" /mnt/var/cache/pacman/pkg ;;
        @snapshots|.snapshots) ;;
        *) echo "   (not mounting extra subvolume $s)" ;;
    esac
done
mount "$ESP" /mnt/boot
findmnt -R /mnt -o TARGET,SOURCE
ls /mnt/boot

say "Last boot's errors (if the journal is persistent)"
journalctl -D /mnt/var/log/journal -b -1 -p err --no-pager 2>/dev/null | tail -30 || true

say "Repairing in chroot: linux-t2, initramfs, systemd-boot"
# the live system is online; let the chroot resolve names too
cp -L /etc/resolv.conf /mnt/etc/resolv.conf 2>/dev/null || true
arch-chroot /mnt /bin/bash -e <<'CHROOT'
grep -q '^\[arch-mact2\]' /etc/pacman.conf || {
    [ -f /etc/pacman.d/arch-mact2-mirrorlist ] ||
        curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/arch-mact2-mirrorlist \
            -o /etc/pacman.d/arch-mact2-mirrorlist
    printf '\n[arch-mact2]\nInclude = /etc/pacman.d/arch-mact2-mirrorlist\nSigLevel = Never\n' >> /etc/pacman.conf
}
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Syyu --noconfirm linux-t2 linux-t2-headers
mkinitcpio -P
bootctl update || bootctl install
echo; echo "--- boot entries ---"
for f in /boot/loader/entries/*.conf; do echo "# $f"; cat "$f"; echo; done
cat /boot/loader/loader.conf 2>/dev/null || true
ls /boot
CHROOT

say "Done"
echo "Check above that an entry uses vmlinuz-linux-t2 + initramfs-linux-t2.img with"
echo "  intel_iommu=on iommu=pt pcie_ports=compat"
echo "Then:  umount -R /mnt; reboot   (pull the USB when the screen goes black)"

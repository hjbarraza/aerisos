#!/bin/bash
# Downgrade linux-t2 on a T2 Mac install and pin it (IgnorePkg), from the live
# USB (as root, WITH internet) or from the installed system (sudo, then reboot):
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/kernel-downgrade.sh | bash
#   VER=7.2.9.arch1-4 curl ... | VER=7.2.9.arch1-4 bash      # another version
#
# Default: 7.2.8.arch1-1, the oldest build the arch-mact2 mirrors still carry
# (7.2.11 has the t2bce_vhci boot panic, t2linux/kernel#37). Rebuilds the
# initramfs and makes the normal "Arch T2" entry the default again.
# Unpin later:  sed -i '/^IgnorePkg = linux-t2/d' /etc/pacman.conf
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
VER=${VER:-7.2.8.arch1-1}
MIRROR=${MIRROR:-https://mirror.funami.tech/arch-mact2/os/x86_64}

if [[ -d /boot/loader/entries && ! -d /run/archiso ]]; then
    R=/; UM=0
else
    ROOT=$(lsblk -pnro NAME,FSTYPE /dev/nvme0n1 | awk '$2=="btrfs"{print $1; exit}')
    ESP=$(lsblk -pnro NAME,FSTYPE /dev/nvme0n1 | awk '$2=="vfat"{print $1; exit}')
    [[ -b $ROOT && -b $ESP ]] || { echo "need a btrfs root and a vfat ESP on /dev/nvme0n1"; lsblk -f; exit 1; }
    umount -R /mnt 2>/dev/null || true
    for d in $ESP $ROOT; do while findmnt -n "$d" >/dev/null; do umount "$d" || break; done; done
    R=/mnt
    mount -o rw "$ROOT" "$R"
    SUBS=$(btrfs subvolume list "$R" | awk '{print $NF}'); SUB=""
    for s in $SUBS; do [[ -d $R/$s/etc && -d $R/$s/usr ]] && { SUB=$s; break; }; done
    umount "$R"; [[ -n $SUB ]] || { echo "no root subvolume found"; exit 1; }
    mount -o "rw,subvol=$SUB" "$ROOT" "$R"
    for s in $SUBS; do case $s in
        @pkg|pkg) mount -o "subvol=$s" "$ROOT" "$R/var/cache/pacman/pkg" ;;
        @log|log) mount -o "subvol=$s" "$ROOT" "$R/var/log" ;;
    esac; done
    mount -o rw "$ESP" "$R/boot"
    cp -L /etc/resolv.conf "$R/etc/resolv.conf" 2>/dev/null || true
    UM=1
fi

echo "== downloading linux-t2 $VER"
D=$R/var/cache/pacman/pkg; mkdir -p "$D"
for p in linux-t2 linux-t2-headers; do
    f="$p-$VER-x86_64.pkg.tar.zst"
    [[ -s $D/$f ]] || curl -fL --progress-bar -o "$D/$f" "$MIRROR/$f"
done

run() { if (( UM )); then arch-chroot "$R" /bin/bash -e -c "$1"; else /bin/bash -e -c "$1"; fi; }
echo "== installing + pinning"
run "pacman -U --noconfirm /var/cache/pacman/pkg/linux-t2-$VER-x86_64.pkg.tar.zst /var/cache/pacman/pkg/linux-t2-headers-$VER-x86_64.pkg.tar.zst
     grep -q '^IgnorePkg = linux-t2' /etc/pacman.conf || sed -i '/^\[options\]/a IgnorePkg = linux-t2 linux-t2-headers' /etc/pacman.conf
     mkinitcpio -P
     pacman -Q linux-t2 linux-t2-headers"
E=$R/boot/loader/entries
MAIN=$(ls "$E"/*t2*.conf | grep -v -e nowifi -e noradio -e nogpu -e vhcilate | head -1)
sed -i "s/^default .*/default $(basename "$MAIN")/; s/^timeout .*/timeout 3/" "$R/boot/loader/loader.conf"
echo "--- loader.conf"; cat "$R/boot/loader/loader.conf"
(( UM )) && { sync; umount -R "$R"; }
echo; echo "Done: linux-t2 $VER installed and pinned. Now:  reboot  (without the USB)."

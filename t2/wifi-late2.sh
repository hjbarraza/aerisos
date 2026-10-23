#!/bin/bash
# T2 Mac panic test: boot with the Broadcom Wi-Fi driver (brcmfmac) kept out of
# early boot. Adds a systemd-boot entry "Arch T2 (wifi late)" next to the normal
# one, makes it the default and shows the menu for 5 s. Run from the live USB
# (as root, no Wi-Fi needed) or from the installed system (sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/wifi-late2.sh | bash
#
# Then reboot 4-5 times. Wi-Fi is off on those boots; once logged in,
# `sudo modprobe brcmfmac` brings it back. Undo:  ... | bash -s undo
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

if mountpoint -q /boot && [[ -d /boot/loader/entries ]]; then
    B=/boot; UM=0                               # on the installed system
else                                            # live USB: mount the ESP
    ESP=$(lsblk -pnro NAME,FSTYPE /dev/nvme0n1 | awk '$2=="vfat"{print $1; exit}')
    [[ -b $ESP ]] || { echo "no vfat ESP on /dev/nvme0n1"; lsblk -f; exit 1; }
    M=/run/aeris-esp; mkdir -p "$M"; mountpoint -q "$M" || mount "$ESP" "$M"
    B=$M; UM=1
fi
E=$B/loader/entries
SRC=$(ls "$E"/*t2*.conf 2>/dev/null | grep -v nowifi | head -1)
[[ -f $SRC ]] || { echo "no T2 boot entry in $E:"; ls "$E"; exit 1; }
NEW=$E/arch-t2-nowifi.conf

if [[ ${1:-} == undo ]]; then
    rm -f "$NEW"
    sed -i "s/^default .*/default $(basename "$SRC")/" "$B/loader/loader.conf"
    echo "removed the wifi-late entry; default is $(basename "$SRC") again"
else
    sed -e 's/^title .*/title Arch T2 (wifi late)/' \
        -e '/^options/{/modprobe.blacklist=brcmfmac/!s/$/ modprobe.blacklist=brcmfmac,brcmfmac_wcc/}' \
        "$SRC" > "$NEW"
    grep -q '^default' "$B/loader/loader.conf" || echo 'default x' >> "$B/loader/loader.conf"
    grep -q '^timeout' "$B/loader/loader.conf" || echo 'timeout 0' >> "$B/loader/loader.conf"
    sed -i 's/^default .*/default arch-t2-nowifi.conf/; s/^timeout .*/timeout 5/' "$B/loader/loader.conf"
    echo "--- $NEW"; cat "$NEW"
fi
echo "--- loader.conf"; cat "$B/loader/loader.conf"
(( UM )) && { sync; umount "$B"; }
echo
echo "Now:  reboot   (4-5 times in a row). Wi-Fi back after login:  sudo modprobe brcmfmac"

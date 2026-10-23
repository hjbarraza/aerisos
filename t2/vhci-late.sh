#!/bin/bash
# Workaround for the linux-t2 7.2.x boot panic in t2bce_vhci (the T2 bridge's
# USB host driver: internal keyboard/trackpad). t2linux/kernel#37: at cold boot a
# firmware event completion can arrive before the driver's workqueue exists ->
# NULL deref on the bce_dma IRQ thread -> "Fatal exception in interrupt".
# Keeps t2bce_vhci out of early boot and loads it from a systemd unit a couple of
# seconds later, when the T2 is quiet. Run from the live USB (as root, no network
# needed) or from the installed system (sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/vhci-late.sh | bash
#
# Adds boot entry "Arch T2 (vhci late)" and makes it the default (menu 5 s).
# The keyboard appears ~3 s after boot. Undo:  ... | bash -s undo
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

if [[ -d /boot/loader/entries && -d /etc/systemd/system && ! -d /run/archiso ]]; then
    R=/; B=/boot; UM=0                           # on the installed system
else                                             # live USB: mount root + ESP
    ROOT=$(lsblk -pnro NAME,FSTYPE /dev/nvme0n1 | awk '$2=="btrfs"{print $1; exit}')
    ESP=$(lsblk -pnro NAME,FSTYPE /dev/nvme0n1 | awk '$2=="vfat"{print $1; exit}')
    [[ -b $ROOT && -b $ESP ]] || { echo "need a btrfs root and a vfat ESP on /dev/nvme0n1"; lsblk -f; exit 1; }
    umount -R /mnt 2>/dev/null || true           # read-only leftovers from diag.sh
    for d in $ESP $ROOT; do while findmnt -n "$d" >/dev/null; do umount "$d" || break; done; done
    R=/run/aeris-root; B=$R/boot
    mkdir -p "$R"; mount -o rw "$ROOT" "$R"
    SUB=""; for s in $(btrfs subvolume list "$R" | awk '{print $NF}'); do [[ -d $R/$s/etc && -d $R/$s/usr ]] && { SUB=$s; break; }; done
    umount "$R"; [[ -n $SUB ]] || { echo "no root subvolume found"; exit 1; }
    mount -o "rw,subvol=$SUB" "$ROOT" "$R"
    mount -o rw "$ESP" "$B"
    touch "$R/.rw" "$B/.rw" && rm "$R/.rw" "$B/.rw" || { echo "not writable"; exit 1; }
    UM=1
fi
E=$B/loader/entries
SRC=$(ls "$E"/*t2*.conf 2>/dev/null | grep -v -e nowifi -e noradio -e nogpu -e vhcilate | head -1)
[[ -f $SRC ]] || { echo "no T2 boot entry in $E:"; ls "$E"; exit 1; }
NEW=$E/arch-t2-vhcilate.conf
UNIT=$R/etc/systemd/system/t2bce-vhci-late.service
WANT=$R/etc/systemd/system/multi-user.target.wants/t2bce-vhci-late.service

if [[ ${1:-} == undo ]]; then
    rm -f "$NEW" "$UNIT" "$WANT"
    sed -i "s/^default .*/default $(basename "$SRC")/" "$B/loader/loader.conf"
    echo "removed the vhci-late entry and unit; default is $(basename "$SRC") again"
else
    cat > "$UNIT" <<'EOF'
[Unit]
Description=Load t2bce_vhci after boot (linux-t2 7.2.x boot race, t2linux/kernel#37)
DefaultDependencies=no
After=systemd-udevd.service local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 2; modprobe t2bce_vhci'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p "$(dirname "$WANT")"; ln -sf ../t2bce-vhci-late.service "$WANT"
    sed -e 's/^title .*/title Arch T2 (vhci late)/' \
        -e '/^options/{/modprobe.blacklist=/!s/$/ modprobe.blacklist=t2bce_vhci/}' \
        "$SRC" > "$NEW"
    grep -q '^default' "$B/loader/loader.conf" || echo 'default x' >> "$B/loader/loader.conf"
    grep -q '^timeout' "$B/loader/loader.conf" || echo 'timeout 0' >> "$B/loader/loader.conf"
    sed -i 's/^default .*/default arch-t2-vhcilate.conf/; s/^timeout .*/timeout 5/' "$B/loader/loader.conf"
    echo "--- $NEW"; cat "$NEW"; echo "--- unit"; cat "$UNIT"
fi
echo "--- loader.conf"; cat "$B/loader/loader.conf"
(( UM )) && { sync; umount "$B"; umount "$R"; }
echo
echo "Now:  reboot   (without the USB; 4-5 times in a row). Keyboard comes ~3 s after boot."

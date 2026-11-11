#!/usr/bin/env bash
# Read, write or restore the RW_LEGACY firmware region. Run on the Chromebook, in Linux.
#
#   ./flash.sh backup               save the current region to rwl_backup.bin
#   ./flash.sh flash IMAGE.bin      write a custom image (made by build.sh)
#   ./flash.sh restore              write MrChromebox's published image back
#
# RW_LEGACY is the only region touched. It is writable with write-protect on, and
# the stock firmware, the developer screen and ChromeOS (Ctrl+D) do not depend on
# it. A bad image breaks only the Ctrl+L boot; see README.md for the way back.
#
# The flashrom build and its options are the ones MrChromebox's firmware script
# uses outside ChromeOS.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
REGION_BYTES=1835008                      # 0x1c0000, RW_LEGACY on octopus (Gemini Lake)
STOCK=rwl_altfw-glk-mrchromebox_20260927.bin
STOCK_URL=https://www.mrchromebox.tech/files/firmware/rw_legacy
FLASHROM_URL=https://www.mrchromebox.tech/files/util/flashrom_ups_int_20260927.tar.gz
die() { echo "✗ $*" >&2; exit 1; }

get_flashrom() {
    [[ -x ./flashrom ]] && return
    curl -fLO "$FLASHROM_URL" && tar -zxf "${FLASHROM_URL##*/}" flashrom || die "could not get flashrom"
}
fr() { sudo ./flashrom -p internal:boardmismatch=force --use-first-chip --fmap "$@"; }

on_ac() { grep -qx 1 /sys/class/power_supply/*/online 2>/dev/null; }

backup() {
    get_flashrom
    rm -f rwl_backup.bin
    fr -i RW_LEGACY:rwl_backup.bin -r -o /tmp/flashrom.log || die "read failed (see /tmp/flashrom.log).
  On this kernel flashrom may need the boot option iomem=relaxed:
    add it to /etc/kernel/cmdline, run 'sudo reinstall-kernels', reboot, try again,
    and remove it afterwards."
    sudo chown "$USER" rwl_backup.bin
    [[ $(stat -c %s rwl_backup.bin) -eq $REGION_BYTES ]] || die "backup is not $REGION_BYTES bytes: this is not the layout the scripts assume. Stop."
    echo "✓ backup: $PWD/rwl_backup.bin ($(md5sum < rwl_backup.bin | cut -d' ' -f1))"
}

write() {
    local image=$1
    [[ -f $image ]] || die "no such file: $image"
    [[ $(stat -c %s "$image") -eq $REGION_BYTES ]] || die "$image is not $REGION_BYTES bytes"
    on_ac || die "plug in the charger first"
    [[ -f rwl_backup.bin ]] || backup
    echo
    echo "About to write $image to RW_LEGACY."
    echo "If it is broken, Ctrl+L stops working and Linux on the card is unreachable until"
    echo "you boot ChromeOS with Ctrl+D and re-run MrChromebox's script there."
    read -rp "Have you checked today that ChromeOS still boots with Ctrl+D? Type YES to write: " answer
    [[ $answer == YES ]] || die "not written"
    get_flashrom
    # -N: verify the written region only.
    fr -i "RW_LEGACY:$image" -w -N -o /tmp/flashrom.log || die "write failed (see /tmp/flashrom.log). Run './flash.sh restore' before you reboot."
    echo "✓ written and verified. Reboot, then Ctrl+L."
}

case ${1:-} in
    backup)  backup ;;
    flash)   write "${2:?usage: flash.sh flash IMAGE.bin}" ;;
    restore) [[ -f $STOCK ]] || { curl -fLO "$STOCK_URL/$STOCK"; curl -fLO "$STOCK_URL/$STOCK.md5"; }
             md5sum -c "$STOCK.md5" || die "download does not match its checksum"
             write "$STOCK" ;;
    *)       sed -n '2,7p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac

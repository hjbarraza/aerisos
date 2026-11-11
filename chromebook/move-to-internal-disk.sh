#!/usr/bin/env bash
# Move the running system from the SD card to the Chromebook's internal disk.
#
#   sudo ~/aerisos/chromebook/move-to-internal-disk.sh            a full run
#   sudo ~/aerisos/chromebook/move-to-internal-disk.sh --resume   finish a run that stopped
#                                                                 after the internal disk was set up
#
# --resume erases nothing: it keeps the copy already on the internal disk, brings it up to
# date from the card (only files that are missing or differ are read), then does steps 4 to 6.
# It also works when the card has gone read-only, because every write goes to the internal disk.
#
# Why: the SD card slot (and the USB 3 ports) on this Chromebook drop out under
# load; the internal disk is on its own bus. This ERASES the internal disk,
# ChromeOS included.
#
# BEFORE YOU RUN IT: ChromeOS is the only way to restore the firmware's RW_LEGACY
# region if a custom image fails to boot. If you still mean to flash the tinyraven
# firmware logo (firmware/flash.sh), do that first.
#
# How it stays safe:
#   - The SD card is only read, never written. If anything fails, power off and
#     boot the card again: you are where you started (minus ChromeOS, once erased).
#   - Nothing is erased until the checks pass: tools, charger, space, and a full
#     read of the card with no disk errors.
#   - The boot image is built on the internal disk itself, inside the copied system.
#   - Every step stops the script on its first error.
set -euo pipefail

TARGET=/dev/mmcblk0                 # internal eMMC
ESP=${TARGET}p1                     # new boot partition (FAT, 1 GiB)
ROOT=${TARGET}p2                    # new system partition (ext4, the rest)
MNT=/mnt/internal
SWAP_BYTES=$((1024 * 1024 * 1024))  # 1 GiB swap file; compressed RAM swap (zram) stays first
# Left behind: caches that refill on their own, and the old swap file.
EXCLUDES=(--exclude=/swapfile --exclude='/var/cache/pacman/pkg/*' --exclude='/var/tmp/*'
          --exclude='/home/*/.cache/*' --exclude='/lost+found' --exclude='/mnt/*')

LOG=/tmp/move-to-internal-disk.log   # in RAM, so it survives a card failure until power-off
ERASED=0                             # set once ChromeOS is gone; decides what a failure message says
NOW="starting"
clock() { printf '%d:%02d' $((SECONDS / 60)) $((SECONDS % 60)); }
# step TITLE [EXPECTED]: a header with the time since start and how long the step usually takes.
step() { NOW=$1; printf '\n\033[1;37m==> %s\033[0m  \033[2m[%s elapsed%s]\033[0m\n' "$1" "$(clock)" "${2:+, takes $2}"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
# What to do when any command fails: which step, what state the disks are in, the next move.
on_error() {
    printf '\n\033[1;31m✗ Stopped in step "%s" (line %s), %s after start.\033[0m\n' "$NOW" "$1" "$(clock)" >&2
    if (( ERASED )); then
        echo "  The internal disk is erased and half-built. The card is unchanged." >&2
        echo "  Next: run this again with --resume. If that fails too, power off, boot the card, run it in full." >&2
    else
        echo "  Nothing was erased. ChromeOS and the card are both unchanged." >&2
    fi
    echo "  Full log: $LOG   Card errors this boot: $(card_errors)" >&2
}
trap 'on_error $LINENO' ERR
# progress DONE TOTAL START LABEL: one self-overwriting line: bar, percent, speed, time left, card errors.
progress() {
    local done=$1 total=$2 start=$3 label=$4 width=28 pct fill rate eta spent
    (( done > total )) && done=$total
    pct=0; rate=0; eta=0; spent=$(( SECONDS - start ))
    (( total > 0 )) && pct=$(( done * 100 / total ))
    (( spent > 0 )) && rate=$(( done / spent ))
    (( rate > 0 ))  && eta=$(( (total - done) / rate ))
    fill=$(( pct * width / 100 ))
    printf '\r  %s [%-*s] %3d%%  %4d/%d MiB  %2d MiB/s  left %d:%02d  card errors %s ' "$label" "$width" \
        "$(printf '%*s' "$fill" '' | tr ' ' '#')" "$pct" $((done >> 20)) $((total >> 20)) $((rate >> 20)) \
        $((eta / 60)) $((eta % 60)) "$(card_errors)"
}
# card_bytes_read: bytes the kernel has read from the card since boot (sectors are 512 bytes).
card_bytes_read() { echo $(( $(awk '{print $3}' "/sys/block/$SRC_DISK/stat") * 512 )); }
# ticker MESSAGE: for steps with no output of their own, print the elapsed time every 10 s.
ticker() { ( t=$SECONDS; while sleep 10; do printf '  … %s, %ds so far, card errors %s\n' "$1" $((SECONDS - t)) "$(card_errors)"; done ) & TICKER=$!; }
ticker_stop() { kill "$TICKER" 2>/dev/null; wait "$TICKER" 2>/dev/null || true; }
# Disk errors the kernel has logged for the card since boot.
card_errors() { journalctl -k -b --no-pager 2>/dev/null | grep -cE "I/O error, dev $SRC_DISK|\[$SRC_DISK\].*FAILED" || true; }

RESUME=0; [[ ${1:-} == --resume ]] && RESUME=1
[[ $EUID -eq 0 ]] || die "Run with sudo."
SRC_PART=$(findmnt -no SOURCE /)                      # e.g. /dev/sda2
SRC_DISK=$(lsblk -no PKNAME "$SRC_PART")              # e.g. sda
OLD_ROOT_UUID=$(findmnt -no UUID /)
OLD_ESP_UUID=$(findmnt -no UUID /efi)
exec > >(tee -a "$LOG") 2>&1
echo "Log: $LOG   Started $(date +%H:%M:%S)   Card: /dev/$SRC_DISK   Target: $TARGET"

if (( RESUME )); then
    step "Resume: use the copy already on the internal disk (nothing is erased)"
    [[ $(lsblk -no FSTYPE "$ESP") == vfat && $(lsblk -no LABEL "$ROOT") == endeavouros ]] ||
        die "$TARGET does not hold a started copy. Run without --resume."
    ERASED=1
    SYSTEM_BYTES=$(df -B1 --output=used "$ROOT" | tail -1)
    NEW_ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
    NEW_ESP_UUID=$(blkid -s UUID -o value "$ESP")
    echo "  found: $(lsblk -no SIZE,FSTYPE,LABEL "$ROOT" | xargs), $(lsblk -no SIZE,FSTYPE,LABEL "$ESP" | xargs)"
    echo "  card: $(findmnt -no OPTIONS / | grep -q emergency_ro && echo 'read-only after errors (fine: it is only read)' || echo writable), card errors this boot: $(card_errors)"
else
step "Checks (nothing is changed yet)" "a few seconds"
[[ $SRC_PART != ${TARGET}* ]] || die "The system already runs from $TARGET."
[[ -b $TARGET ]] || die "$TARGET not found."
for tool in rsync sfdisk wipefs mkfs.vfat mkfs.ext4 mkswap bootctl reinstall-kernels udevadm tar chroot; do
    command -v "$tool" >/dev/null || die "Missing tool: $tool"
done
echo "  tools: all present"
findmnt -no OPTIONS / | grep -qw rw || die "The card is mounted read-only (it has already failed this boot). Reboot and run this first thing."
echo "  card: writable"
grep -qx 1 /sys/class/power_supply/*/online 2>/dev/null || die "Plug in the charger."
echo "  charger: connected, battery $(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo '?')%"
echo "  measuring the system (about 30 s)…"
SYSTEM_BYTES=$(( $(du -sxB1 "${EXCLUDES[@]}" / | cut -f1) + $(du -sxB1 /efi | cut -f1) ))
need=$(( SYSTEM_BYTES + SWAP_BYTES + 1024 * 1024 * 1024 ))   # system + swap + 1 GiB to work in
have=$(( $(lsblk -bdno SIZE "$TARGET") - 1024 * 1024 * 1024 ))                           # minus the boot partition
(( need < have )) || die "Not enough room: need $((need >> 20)) MiB, the internal disk offers $((have >> 20)) MiB."
echo "  space: $((need >> 20)) MiB needed, $((have >> 20)) MiB available"
(( $(card_errors) == 0 )) || die "The card has already logged disk errors this boot. Reboot and run this first thing, before other work."
echo "  card errors this boot: 0"

step "Read test: every file on the card, once" "5 to 8 min"
echo "  $((SYSTEM_BYTES >> 20)) MiB to read. Nothing is written or erased in this step."
# If the card cannot be read end to end right now, stop before ChromeOS is erased.
# tar exits 1 when a file changed while it was read, which is normal on a running system;
# 2 means it could not read something.
base=$(card_bytes_read); start=$SECONDS
( while sleep 1; do progress $(( $(card_bytes_read) - base )) "$SYSTEM_BYTES" "$start" "reading"; done ) & BAR=$!
for dir in / /efi; do
    rc=0; tar --one-file-system "${EXCLUDES[@]}" -cf - "$dir" 2>/dev/null | cat > /dev/null || rc=$?
    (( rc <= 1 )) || { kill "$BAR" 2>/dev/null; die "Could not read all of $dir from the card. Nothing was erased."; }
done
kill "$BAR" 2>/dev/null; wait "$BAR" 2>/dev/null || true
progress "$SYSTEM_BYTES" "$SYSTEM_BYTES" "$start" "reading"; echo
(( $(card_errors) == 0 )) || die "The card logged disk errors during the read test. Nothing was erased. Reboot and try again."
echo "  read test passed in $(( (SECONDS - start) / 60 )) min $(( (SECONDS - start) % 60 )) s, no disk errors"

echo
lsblk -o NAME,SIZE,FSTYPE,LABEL "$TARGET"
echo
echo "This ERASES ALL DATA on $TARGET (ChromeOS) and copies this system onto it."
echo "With ChromeOS gone, MrChromebox's script can no longer restore the firmware from ChromeOS."
read -rp "Type ERASE to continue: " answer
[[ $answer == ERASE ]] || die "Stopped. Nothing was changed."

ERASED=1
echo "  Plan from here: partition (seconds), file systems (seconds), copy (8 to 12 min),"
echo "  settings (seconds), boot image (3 to 6 min), verify (seconds)."

step "1/6 Partition $TARGET: 1 GiB boot, the rest system" "a few seconds"
for part in "$TARGET"p*; do umount -q "$part" 2>/dev/null || true; done
wipefs -a "$TARGET" >/dev/null
sfdisk --quiet "$TARGET" <<'EOF'
label: gpt
size=1GiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="endeavouros"
EOF
udevadm settle

step "2/6 File systems" "about 20 s"
mkfs.vfat -F32 -n EFI "$ESP" >/dev/null
mkfs.ext4 -q -F -L endeavouros "$ROOT"
NEW_ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
NEW_ESP_UUID=$(blkid -s UUID -o value "$ESP")
lsblk -o NAME,SIZE,FSTYPE,LABEL "$TARGET" | sed 's/^/  /'

fi

step "3/6 Copy the system (the card is only read)" "8 to 12 min"
echo "  $((SYSTEM_BYTES >> 20)) MiB to copy. The line below shows: bytes copied, percent, speed, time left."
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$ROOT" "$MNT"
mkdir -p "$MNT/efi"
mountpoint -q "$MNT/efi" || mount "$ESP" "$MNT/efi"
(( RESUME )) && echo "  Resuming: only files that are missing or differ are read from the card."
errors_before=$(card_errors)
# -x stays on the card's system partition: /proc, /sys, /dev, /run, /tmp and /efi are other
# file systems and come across as empty folders. /efi is copied next, for its layout.
# rsync exits 24 when a file vanished while it ran (a temporary file on a running system); fine.
# --no-inc-recursive lists every file first, so the percentage is true from the start.
rc=0; rsync -aAXHx --numeric-ids --no-inc-recursive --info=progress2 "${EXCLUDES[@]}" / "$MNT/" || rc=$?
(( rc == 0 || rc == 24 )) || die "The copy is incomplete (rsync exit $rc: some files could not be read). Run this again with --resume."
echo "  system copied; now the boot partition…"
rc=0; rsync -rt --info=progress2 /efi/ "$MNT/efi/" || rc=$?
(( rc == 0 )) || die "The boot partition copy failed (rsync exit $rc). Run this again with --resume."
echo "  copied: $(df -h --output=used "$MNT" | tail -1 | xargs) on the system partition, $(df -h --output=used "$MNT/efi" | tail -1 | xargs) on the boot partition"
# rsync reports any file it could not read (exit 23), and the checks above stop on that. So if
# we are here, every file was read. Card errors logged meanwhile were retried reads or writes
# the card's own system tried; they are worth knowing, not a reason to stop.
errors_now=$(card_errors)
if (( errors_now > errors_before )); then
    echo "  note: the card logged $((errors_now - errors_before)) disk errors during the copy, but every file was read (rsync reported none unreadable)."
fi

step "4/6 Point the copy at its new disk" "a few seconds"
sed -i "s/$OLD_ROOT_UUID/$NEW_ROOT_UUID/g; s/$OLD_ESP_UUID/$NEW_ESP_UUID/g" "$MNT/etc/fstab"
# The kernel options: new root, and without the temporary flash-tool option if it was left in.
sed -i "s/$OLD_ROOT_UUID/$NEW_ROOT_UUID/g; s/ iomem=relaxed//g" "$MNT/etc/kernel/cmdline"
grep -q "$NEW_ROOT_UUID" "$MNT/etc/fstab" "$MNT/etc/kernel/cmdline" || die "Could not update fstab or the kernel options."
[[ -f $MNT/swapfile ]] || mkswap --quiet --size "$SWAP_BYTES" --file "$MNT/swapfile"
# Make sure the boot image carries the internal disk's drivers (only those this kernel has).
drivers=""
for module in mmc_core mmc_block sdhci sdhci_pci sdhci_acpi cqhci; do
    modinfo "$module" >/dev/null 2>&1 && drivers+=" $module"
done
echo "add_drivers+=\"$drivers \"" > "$MNT/etc/dracut.conf.d/internal-disk.conf"
echo "  fstab and kernel options updated, 1 GiB swap file made, boot drivers:$drivers"

step "5/6 Build the boot image and boot entries on the internal disk" "3 to 6 min"
echo "  This step prints little. The card is not used here; all writes go to the internal disk."
# Done inside the copied system, so every write lands on the internal disk.
for fs in dev proc sys run; do mount --rbind "/$fs" "$MNT/$fs"; mount --make-rslave "$MNT/$fs"; done
ticker "building the boot image"
chroot "$MNT" reinstall-kernels || { ticker_stop; false; }
ticker_stop
chroot "$MNT" bootctl --esp-path=/efi --no-variables install >/dev/null
echo "  boot image built, boot loader installed"
for fs in run sys proc dev; do umount -R "$MNT/$fs"; done

step "6/6 Verify" "a few seconds"
entries=("$MNT"/efi/loader/entries/*.conf)
grep -L "$NEW_ROOT_UUID" "${entries[@]}" | grep -q . && die "A boot entry does not point at the new system partition."
grep -l "$OLD_ROOT_UUID" "${entries[@]}" | grep -q . && die "A boot entry still points at the card."
grep -h '^initrd\|^linux' "${entries[@]}" | awk '{print $2}' | sort -u | while read -r file; do
    [[ -s $MNT/efi$file ]] || die "Missing or empty boot file: $file"
done
[[ -s $MNT/efi/EFI/BOOT/BOOTX64.EFI ]] || die "The boot loader is missing from the boot partition."
echo "  boot entries: $(grep -h '^title' "${entries[@]}" | sed 's/^title *//' | paste -sd, -)"
echo "  system: $(df -h --output=used,avail "$MNT" | tail -1 | awk '{print $1" used, "$2" free"}')"
sync
umount -R "$MNT"

cat <<EOF

Done in $(clock). The system is on the internal disk; the card is unchanged.
  1. Power off.   2. Take the card out.   3. Power on, Ctrl+L.
If the boot menu of the firmware appears, pick the internal disk under Boot Manager.
Check after login:  findmnt -no SOURCE /   must print $ROOT
If it does not boot: put the card back in and boot it as before.
At the white screen never press Space or Enter: with ChromeOS gone that needs a recovery USB.
EOF

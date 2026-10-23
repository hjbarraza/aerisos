#!/bin/bash
# Diagnose a T2 Mac AerisOS install that kernel-panics. Run from the live USB
# shell (as root), with Wi-Fi up:
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/t2/diag.sh | bash
#
# Mounts the install read-only, collects what the panicked boots logged (journal,
# pacman log, boot entries, kernels, modules, hardware), writes it all to
# /root/t2-diag.txt and prints the key parts. Add DIAG_UPLOAD=1 to also upload
# the report to paste.rs and print the URL (so it can be read from another
# machine):
#
#   curl -fsSL .../t2/diag.sh | DIAG_UPLOAD=1 bash
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
OUT=/root/t2-diag.txt
: > "$OUT"
log() { printf '%s\n' "$*" | tee -a "$OUT"; }
sec() { log; log "=================== $* ==================="; }
run() { log "\$ $*"; "$@" 2>&1 | tee -a "$OUT"; }
quiet() { log "\$ $*"; "$@" >> "$OUT" 2>&1; }

sec "Finding the install"
DISK=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1 ~ /nvme/ {print $1; exit}')
ROOT=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2=="btrfs"{print $1; exit}')
ESP=$(lsblk -pnro NAME,FSTYPE "$DISK" | awk '$2=="vfat"{print $1; exit}')
log "disk $DISK   root $ROOT   esp $ESP"
[[ -b $ROOT && -b $ESP ]] || { log "could not find the install"; lsblk -f | tee -a "$OUT"; exit 1; }

umount -R /mnt 2>/dev/null || true
mount -o ro "$ROOT" /mnt
SUBS=$(btrfs subvolume list /mnt | awk '{print $NF}')
ROOTSUB=""
for s in $SUBS; do [[ -d /mnt/$s/etc && -d /mnt/$s/usr ]] && { ROOTSUB=$s; break; }; done
umount /mnt
[[ -n $ROOTSUB ]] || { log "no root subvolume among: $SUBS"; exit 1; }
mount -o "ro,subvol=$ROOTSUB" "$ROOT" /mnt
for s in $SUBS; do case $s in @log|log) mount -o "ro,subvol=$s" "$ROOT" /mnt/var/log ;; esac; done
mount -o ro "$ESP" /mnt/boot
log "root subvolume $ROOTSUB   (all: $(echo $SUBS))"

sec "Live system (this USB)"
run uname -r
run dmesg -l err,crit,alert,emerg

sec "Installed kernels and boot entries"
run ls -la /mnt/boot
run cat /mnt/boot/loader/loader.conf
for f in /mnt/boot/loader/entries/*.conf; do log "--- $f"; cat "$f" | tee -a "$OUT"; done
run cat /mnt/etc/mkinitcpio.conf
run ls /mnt/etc/mkinitcpio.d
run cat /mnt/etc/modprobe.d/*.conf
run cat /mnt/etc/modules-load.d/*.conf
run cat /mnt/etc/fstab

sec "Installed packages of interest"
for p in linux-t2 linux-t2-headers linux linux-firmware mkinitcpio systemd mesa amdgpu apple-bce apple-t2-audio-config; do
    grep -h "installed $p \|upgraded $p " /mnt/var/log/pacman.log 2>/dev/null | tail -2
done | tee -a "$OUT"
run grep -c . /mnt/etc/pacman.conf
run grep -nE '^\[|^Include' /mnt/etc/pacman.conf

sec "pacman log: last 60 changes"
grep -E 'upgraded|installed|removed|starting full' /mnt/var/log/pacman.log | tail -60 | tee -a "$OUT"

J=/mnt/var/log/journal
sec "Boots recorded in the journal"
run journalctl -D "$J" --list-boots --no-pager
for b in -1 -2 -3; do
    sec "Boot $b: kernel + errors"
    journalctl -D "$J" -b $b -k --no-pager 2>/dev/null | head -5 | tee -a "$OUT"
    log "--- errors (-p err) ---"
    journalctl -D "$J" -b $b -p err --no-pager 2>/dev/null | tail -40 | tee -a "$OUT"
    log "--- last 40 lines before it stopped ---"
    journalctl -D "$J" -b $b --no-pager 2>/dev/null | tail -40 | tee -a "$OUT"
done

sec "Kernel-side crash traces in the journal (any boot)"
journalctl -D "$J" -k --no-pager 2>/dev/null | grep -nE 'BUG:|Oops|panic|Call Trace|RIP:|general protection|NULL pointer|amdgpu.*(hang|timeout|reset)|apple.bce|brcmfmac.*(fail|error)' | tail -60 | tee -a "$OUT"

sec "pstore (panic text saved by firmware, if any)"
run ls -la /sys/fs/pstore
for f in /sys/fs/pstore/*; do [[ -f $f ]] && { log "--- $f"; tail -60 "$f" | tee -a "$OUT"; }; done

sec "Hardware"
run lspci -nn
run lsmod
quiet dmidecode -t system

sec "Done"
log "Full report: $OUT  ($(wc -l < "$OUT") lines)"
if [[ ${DIAG_UPLOAD:-0} == 1 ]]; then
    URL=$(curl -fsS --data-binary @"$OUT" https://paste.rs 2>/dev/null)
    log "Uploaded: $URL"
else
    log "Upload it (prints a URL to read elsewhere):  curl --data-binary @$OUT https://paste.rs"
fi
log "The install stays mounted read-only at /mnt;  umount -R /mnt  when done."

#!/bin/bash
# Build the AerisOS installer and write it to a USB stick, in one command.
# Run as your normal user on an Arch machine that has this repo at ~/aerisos:
#
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/iso/usb.sh | bash
#   ... | bash -s -- --snapshot   first save this machine's configs and package lists
#   ... | bash -s -- --t2         the T2 Mac stick (run on the T2 Mac: it holds the firmware)
#
# Asks which stick first, then pulls the repo, builds (iso/build.sh, about 15 minutes) and
# writes. Questions read /dev/tty because stdin is the pipe from curl.
set -euo pipefail

AERIS=${AERIS:-$HOME/aerisos}
NAME=aerisos
BUILD_ARGS=()
SNAPSHOT=0
for arg in "$@"; do
  case $arg in
    --t2) NAME=aerisos-t2; BUILD_ARGS=(--t2) ;;
    --snapshot) SNAPSHOT=1 ;;
    *) echo "usage: usb.sh [--snapshot] [--t2]" >&2; exit 1 ;;
  esac
done

die() { echo "! $*" >&2; exit 1; }
(( EUID != 0 )) || die "run as your normal user (it asks for the sudo password)"
[[ -x $AERIS/iso/build.sh ]] || die "no AerisOS repo at $AERIS"

# --- the stick, asked before the long build -----------------------------------
mapfile -t STICKS < <(lsblk -dpno NAME,TRAN,SIZE,MODEL | awk '$2 == "usb"')
(( ${#STICKS[@]} )) || die "no USB stick found"
for i in "${!STICKS[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${STICKS[$i]}"; done
N=1
if (( ${#STICKS[@]} > 1 )); then read -rp "Stick number: " N </dev/tty; fi
[[ $N =~ ^[0-9]+$ ]] && (( N >= 1 && N <= ${#STICKS[@]} )) || die "invalid choice"
read -r STICK _ <<<"${STICKS[$((N - 1))]}"
read -rp "Type ERASE to wipe $STICK: " CONFIRM </dev/tty
[[ $CONFIRM == "ERASE" ]] || die "nothing written"

# One password prompt: keep sudo alive through the build, for the write at the end
sudo -v
while sudo -n true; do sleep 50; done &
trap "kill $! 2>/dev/null || true" EXIT

# --- the repo: the ISO carries it at HEAD ---------------------------------------
git -C "$AERIS" pull --ff-only
if (( SNAPSHOT )); then
  "$AERIS/setup.sh" snapshot </dev/tty
  git -C "$AERIS" add dotfiles packages
  if ! git -C "$AERIS" diff --cached --quiet; then
    git -C "$AERIS" commit -q -m "Snapshot: $HOSTNAME"
    echo "Snapshot committed, not pushed. Review it, then: git -C $AERIS push"
  fi
fi

# --- build, then write -----------------------------------------------------------
sudo "$AERIS/iso/build.sh" "${BUILD_ARGS[@]}"
ISO=$(ls -t "$AERIS/iso/out/$NAME"-[0-9]*.iso | head -1)

sudo umount "$STICK"?* 2>/dev/null || true
sudo dd if="$ISO" of="$STICK" bs=4M status=progress oflag=sync
echo "Done: ${ISO##*/} is on $STICK. Boot from it and run: aeris-installer"

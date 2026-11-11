#!/usr/bin/env bash
# Build a RW_LEGACY firmware image whose boot logo is the tinyraven mark instead
# of the coreboot hare. Run on an x86_64 Arch Linux machine (not the Chromebook:
# two slow cores and an SD card make the toolchain build take hours).
#
#   ./build.sh            -> ~/build/tinyraven-firmware/rwl_tinyraven.bin
#
# It follows MrChromebox's own steps (docs.mrchromebox.tech, "Compiling Your Own
# Firmware") and his build-rwl_payload.sh, pinned to one release:
#   1. installs the build packages
#   2. clones MrChromebox's coreboot at $TAG and builds the i386 toolchain (slow, once)
#   3. points the build at logo.png and builds the edk2 RW_LEGACY payload
#   4. wraps the payload in a CBFS image of the RW_LEGACY region size
#   5. prints our image next to MrChromebox's published one, to compare by eye
#
# Nothing here touches a Chromebook. Flashing is flash.sh, run on the Chromebook.
# MrChromebox does not support self-built RW_LEGACY payloads; see README.md for risks.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WORK="${WORK:-$HOME/build/tinyraven-firmware}"
TAG=MrChromebox-2609                      # coreboot branch; its script pins edk2 to uefipayload_rwl_2609
REGION_SIZE=0x1c0000                      # RW_LEGACY on octopus (Gemini Lake): 1,835,008 bytes
STOCK=rwl_altfw-glk-mrchromebox_20260927.bin
STOCK_URL=https://www.mrchromebox.tech/files/firmware/rw_legacy
log() { printf '\n\033[1;37m■ %s\033[0m\n' "$*"; }

log "Build packages"
packages=(base-devel curl git gcc-ada ncurses zlib nasm imagemagick pkgconf cmocka nss)
# Ask for the password only when something is missing, so a later run needs no terminal.
pacman -Q "${packages[@]}" >/dev/null 2>&1 || sudo pacman --needed --noconfirm -S "${packages[@]}"
# The edk2 Makefile calls ImageMagick's old `convert` name.
command -v convert >/dev/null || { echo "ImageMagick 'convert' not found; install it or link it to 'magick'." >&2; exit 1; }

log "Source: MrChromebox coreboot, $TAG"
mkdir -p "$WORK"; cd "$WORK"
[[ -d coreboot ]] || git clone https://github.com/mrchromebox/coreboot.git
cd coreboot
git fetch --tags origin "$TAG"
git checkout "$TAG"
git submodule update --init --checkout --recursive

log "Toolchain (about an hour the first time, skipped afterwards)"
[[ -x util/crossgcc/xgcc/bin/i386-elf-gcc ]] || make crossgcc-i386 CPUS="$(nproc)"

log "Payload with the tinyraven logo"
# The build converts this file to a 24-bit BMP and compiles it into the payload.
# edk2 draws it centred and unscaled; logo.png is 480x400, cut from the centre of the
# 1366x768 boot splash, so the firmware logo and the Linux splash line up.
grep -q EDK2_BOOTSPLASH_FILE build-rwl_payload.sh ||
    sed -i "/^CONFIG_EDK2_DISABLE_TPM=y/a CONFIG_EDK2_BOOTSPLASH_FILE=\"$HERE/logo.png\"" build-rwl_payload.sh
grep -q "EDK2_BOOTSPLASH_FILE=\"$HERE/logo.png\"" build-rwl_payload.sh || { echo "Could not set the logo path in build-rwl_payload.sh" >&2; exit 1; }
./build-rwl_payload.sh

log "RW_LEGACY image"
# MrChromebox does not publish this step. His image holds one LZMA-compressed CBFS
# file named "payload"; the stock firmware loads that name.
out="$WORK/rwl_tinyraven.bin"
rm -f "$out"
build/cbfstool "$out" create -m x86 -s "$REGION_SIZE"
build/cbfstool "$out" add-payload -f rwl_payload.fd -n payload -c lzma
[[ $(stat -c %s "$out") -eq $((REGION_SIZE)) ]] || { echo "Image is not $REGION_SIZE bytes" >&2; exit 1; }

log "Compare with MrChromebox's published image"
cd "$WORK"
[[ -f $STOCK ]] || { curl -fLO "$STOCK_URL/$STOCK"; curl -fLO "$STOCK_URL/$STOCK.md5"; md5sum -c "$STOCK.md5"; }
echo "--- ours:";      coreboot/build/cbfstool "$out" print
echo "--- published:"; coreboot/build/cbfstool "$STOCK" print
echo
echo "Both must show one file named 'payload' of type 'simple elf' (payload), LZMA-compressed,"
echo "in an image of the same size. If they differ in anything but the payload's size, stop."
echo
echo "Image: $out"
echo "Next:  copy it to the Chromebook and run flash.sh there."

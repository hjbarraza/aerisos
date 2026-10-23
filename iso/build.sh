#!/usr/bin/env bash
# Build the AerisOS installer ISO (bootable USB), Omarchy-style.
#
#   sudo ~/aerisos/iso/build.sh
#
# Takes the official Arch "releng" ISO profile and bakes in:
#   - this repo at its current commit (git archive → /root/aerisos on the ISO,
#     so gitignored secrets never reach the ISO)
#   - the guided installer (aeris-installer) + a login hint to run it
# Output: ~/aerisos/iso/out/aerisos-<date>-x86_64.iso  (~1.2 GB, gitignored)
#
# T2 Macs:  sudo ~/aerisos/iso/build.sh --t2   (on a working T2 Mac, or anywhere with T2_FIRMWARE_TAR, below)
#   live system on the linux-t2 kernel (internal keyboard/trackpad work), the
#   arch-mact2 repo, and this Mac's fetched Apple Wi-Fi/Bluetooth firmware baked
#   in, so Wi-Fi works on the USB and on the installed system without tethering.
#   The firmware is Apple's: keep that ISO to yourself.
#
# Write it to a USB stick (ERASES the stick):
#   sudo cp iso/out/aerisos-*.iso /dev/sdX && sync
#
# --t2 on a machine that isn't a T2 Mac: T2_FIRMWARE_TAR=/path/firmware.tar sudo -E ./build.sh --t2
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
T2=0
case ${1:-} in
    --t2) T2=1 ;;
    "")   lspci | grep -i 'T2 Bridge' >/dev/null && echo "Note: this is a T2 Mac; for a T2 installer use --t2" ;;
    *)    echo "usage: build.sh [--t2]" >&2; exit 1 ;;
esac

AERIS="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=/var/tmp/aerisos-iso-work          # mkarchiso scratch (needs a few GB)
PROFILE="$WORK/profile"
OUT="$AERIS/iso/out"

echo "== 1/4 archiso =="
pacman -S --needed --noconfirm archiso

echo "== 2/4 profile: releng + AerisOS additions =="
rm -rf "$WORK"
mkdir -p "$PROFILE" "$OUT"
cp -a /usr/share/archiso/configs/releng/. "$PROFILE"

# The repo, clean at HEAD (committed files only; .gitignore'd secrets stay out)
mkdir -p "$PROFILE/airootfs/root/aerisos"
git -C "$AERIS" archive HEAD | tar -x -C "$PROFILE/airootfs/root/aerisos"

# The installer
install -Dm755 "$AERIS/iso/aeris-installer" "$PROFILE/airootfs/usr/local/bin/aeris-installer"

# Login hint on the live system
mkdir -p "$PROFILE/airootfs/etc/profile.d"
cat > "$PROFILE/airootfs/etc/profile.d/aerisos.sh" <<'EOF'
printf '\n  \033[1mAerisOS\033[0m — to install, run:  \033[1maeris-installer\033[0m\n  (Wi-Fi first if needed: iwctl)\n\n'
EOF

# Boot menu says AerisOS, not "Arch Linux install medium" (GRUB on UEFI —
# what a Mac shows — plus systemd-boot entries and BIOS syslinux)
grep -rlZ "Arch Linux install medium" "$PROFILE/grub" "$PROFILE/efiboot" "$PROFILE/syslinux" 2>/dev/null \
    | xargs -r0 sed -i 's/Arch Linux install medium/AerisOS installer/g'
sed -i 's/Arch Linux/AerisOS/g' "$PROFILE/syslinux/archiso_head.cfg" 2>/dev/null || true

# Branding + permissions in profiledef.sh
sed -i \
    -e 's/^iso_name=.*/iso_name="aerisos"/' \
    -e 's/^iso_label=.*/iso_label="AERISOS_$(date +%Y%m)"/' \
    -e 's/^iso_publisher=.*/iso_publisher="AerisOS"/' \
    -e 's/^iso_application=.*/iso_application="AerisOS installer"/' \
    "$PROFILE/profiledef.sh"
sed -i '/^file_permissions=(/a\  ["/usr/local/bin/aeris-installer"]="0:0:755"' "$PROFILE/profiledef.sh"

if (( T2 )); then
    echo "== T2 variant: linux-t2 kernel, arch-mact2 repo, Apple Wi-Fi firmware =="
    printf '\n[arch-mact2]\nInclude = %s\nSigLevel = Never\n' "$AERIS/t2/arch-mact2-mirrorlist" >> "$PROFILE/pacman.conf"
    sed -i 's/^linux$/linux-t2/' "$PROFILE/packages.x86_64"
    grep -rlZ 'vmlinuz-linux' "$PROFILE/grub" "$PROFILE/efiboot" "$PROFILE/syslinux" \
        | xargs -r0 sed -i 's/vmlinuz-linux/vmlinuz-linux-t2/g; s/initramfs-linux\.img/initramfs-linux-t2.img/g'
    echo 'kernel_params_x86_64="intel_iommu=on iommu=pt pcie_ports=compat"' >> "$PROFILE/profiledef.sh"
    sed -i 's/^iso_name=.*/iso_name="aerisos-t2"/' "$PROFILE/profiledef.sh"

    # Firmware the fetcher put in /usr/lib/firmware/brcm (no package owns it). The list
    # tells aeris-installer what to copy onto the new system
    mapfile -t FW < <(comm -23 <(find /usr/lib/firmware/brcm -type f | sort) <(pacman -Qlq | sort))
    if [[ -n ${T2_FIRMWARE_TAR:-} ]]; then
        # Not on a T2 Mac: use a firmware.tar made there (flat brcm files, e.g. the T2FW stick's)
        mkdir -p "$PROFILE/airootfs/usr/lib/firmware/brcm" "$PROFILE/airootfs/usr/local/share/aerisos"
        tar -xf "$T2_FIRMWARE_TAR" -C "$PROFILE/airootfs/usr/lib/firmware/brcm"
        find "$PROFILE/airootfs/usr/lib/firmware/brcm" -type f -printf '/usr/lib/firmware/brcm/%P\n' \
            > "$PROFILE/airootfs/usr/local/share/aerisos/t2-firmware.list"
        echo "   $(wc -l < "$PROFILE/airootfs/usr/local/share/aerisos/t2-firmware.list") firmware files baked in from $T2_FIRMWARE_TAR"
    elif (( ${#FW[@]} )); then
        mkdir -p "$PROFILE/airootfs/usr/lib/firmware/brcm" "$PROFILE/airootfs/usr/local/share/aerisos"
        cp -a "${FW[@]}" "$PROFILE/airootfs/usr/lib/firmware/brcm/"
        printf '%s\n' "${FW[@]}" > "$PROFILE/airootfs/usr/local/share/aerisos/t2-firmware.list"
        echo "   ${#FW[@]} firmware files baked in"
    else
        echo "   ! no fetched Apple firmware here: Wi-Fi on the USB will need t2/firmware.sh (phone tethering)"
    fi
fi

echo "== 3/4 mkarchiso (downloads packages; takes a while) =="
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"

echo "== 4/4 cleanup =="
rm -rf "$WORK"
chown -R "${SUDO_USER:-root}:${SUDO_USER:-root}" "$OUT"

echo
ls -lh "$OUT"/aerisos-*.iso
echo "Write to USB (ERASES it):  sudo cp $OUT/aerisos-*.iso /dev/sdX && sync"

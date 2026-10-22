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
# Write it to a USB stick (ERASES the stick):
#   sudo cp iso/out/aerisos-*.iso /dev/sdX && sync
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

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

echo "== 3/4 mkarchiso (downloads packages; takes a while) =="
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"

echo "== 4/4 cleanup =="
rm -rf "$WORK"
chown -R "${SUDO_USER:-root}:${SUDO_USER:-root}" "$OUT"

echo
ls -lh "$OUT"/aerisos-*.iso
echo "Write to USB (ERASES it):  sudo cp $OUT/aerisos-*.iso /dev/sdX && sync"

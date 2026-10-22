#!/usr/bin/env bash
# AerisOS bootstrap for a NEW machine.
#
# Start from a minimal Arch Linux install (archinstall is fine), log in as root:
#
#   pacman -Sy --noconfirm git
#   git clone https://github.com/hjbarraza/aerisos.git /root/aerisos
#   bash /root/aerisos/install.sh
#
# The repo is private: HTTPS asks for your GitHub username + a personal access
# token (classic, "repo" scope), or clone over SSH if your key is set up.
#
# This script creates your user account (username + password), gives it sudo,
# puts the repo in your home, and hands over to setup.sh — which asks the rest
# (the wizard) and installs everything, Hyprland included.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root on a fresh Arch install (see the header of this file)." >&2; exit 1; }

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

echo "== AerisOS install: user account =="
read -rp "Username for your account: " NEW_USER
[[ $NEW_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid username (lowercase, no spaces)." >&2; exit 1; }

if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists; keeping it."
else
    useradd -m -G wheel -s /bin/bash "$NEW_USER"
fi
echo "Set $NEW_USER's password:"
passwd "$NEW_USER"

echo "== sudo for the wheel group =="
pacman -S --needed --noconfirm sudo git
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

echo "== Moving the repo into /home/$NEW_USER/aerisos =="
DEST="/home/$NEW_USER/aerisos"
if [[ $HERE == "$DEST" ]]; then
    :
elif [[ -e $DEST ]]; then
    echo "$DEST already exists; using it as it is."
else
    cp -a "$HERE" "$DEST"
fi
chown -R "$NEW_USER:$NEW_USER" "$DEST"

echo
echo "== Handing over to setup.sh as $NEW_USER (sudo will ask for the password you just set) =="
exec su - "$NEW_USER" -c "cd ~/aerisos && ./setup.sh"

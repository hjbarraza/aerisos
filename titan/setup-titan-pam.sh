#!/usr/bin/env bash
# Titan security key: password + key 2FA for hyprlock and SDDM login,
# and log out when the key is unplugged.
#
# Run as root:  sudo bash ~/aerisos/titan/setup-titan-pam.sh
# (or ./setup.sh titan, which runs this)
#
# Scope (deliberate):
#   - Only /etc/pam.d/hyprlock and /etc/pam.d/sddm get the U2F factor.
#   - tty login (Ctrl+Alt+F3) stays password-only as the recovery path
#     if the key is ever lost or broken.
#   - Unplugging the key (Feitian/Titan 096e:085b) terminates all of the
#     user's sessions via udev, then restarts SDDM (sddm-helper crashes on
#     terminate-user and the greeter is never respawned otherwise).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

# The account to protect: the user who ran sudo
TARGET_USER="${SUDO_USER:-}"
[[ -n $TARGET_USER && $TARGET_USER != root ]] || { echo "run with sudo from your normal account, not as root" >&2; exit 1; }

U2F_LINE='auth        required    pam_u2f.so authfile=/etc/u2f_mappings cue'

echo "== 1/4 installing pam-u2f =="
pacman -S --needed --noconfirm pam-u2f

if [[ -s /etc/u2f_mappings ]]; then
    echo "== 2/4 key already enrolled in /etc/u2f_mappings; skipping (delete it to re-enroll) =="
else
    echo "== 2/4 enrolling the key: TOUCH the Titan key when it blinks =="
    # pamu2fcfg talks to the FIDO key and waits for a touch (and PIN, if one is set).
    pamu2fcfg -u "$TARGET_USER" > /etc/u2f_mappings.new
    # Public key handles only, not secrets; must be world-readable because
    # hyprlock runs PAM as the normal user.
    install -m 644 -o root -g root /etc/u2f_mappings.new /etc/u2f_mappings
    rm /etc/u2f_mappings.new
    echo "enrolled: $(cut -c1-40 /etc/u2f_mappings)..."
fi

echo "== 3/4 patching PAM (hyprlock + sddm) =="
if ! grep -q pam_u2f /etc/pam.d/hyprlock; then
    sed -i "/^auth\s*include\s*login/a $U2F_LINE" /etc/pam.d/hyprlock
fi
if ! grep -q pam_u2f /etc/pam.d/sddm; then
    sed -i "/^auth\s*include\s*system-login/a $U2F_LINE" /etc/pam.d/sddm
fi
grep -H pam_u2f /etc/pam.d/hyprlock /etc/pam.d/sddm

echo "== 4/4 udev rule: log out $TARGET_USER when the Titan key is unplugged =="
cat > /etc/udev/rules.d/90-titan-logout.rules <<EOF
# Google Titan key (Feitian 096e:085b) removed -> end all of $TARGET_USER's sessions,
# then restart SDDM so the login screen comes back (sddm-helper crashes on
# terminate-user and the greeter is never respawned otherwise).
ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="96e/85b/*", RUN+="/usr/bin/sh -c '/usr/bin/loginctl terminate-user $TARGET_USER; /usr/bin/systemctl --no-block restart sddm'"
EOF
udevadm control --reload

echo
echo "DONE. Test NOW, before unplugging anything:"
echo "  1. Lock the screen. Unlock = type password, then touch the blinking key."
echo "  2. Only after that works, try unplugging the key: you should be logged out."
echo "Recovery if unlock ever fails: Ctrl+Alt+F3 tty login (password only)."

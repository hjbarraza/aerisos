#!/usr/bin/env bash
# Security key (Google Titan, YubiKey, or any FIDO2/U2F key):
# password + key 2FA for hyprlock and SDDM login, and log out when the
# key is unplugged. The plugged-in key is auto-detected.
#
# Run as root:  sudo bash ~/aerisos/titan/setup-titan-pam.sh
# (or ./setup.sh titan, which runs this; the wizard offers it too)
# Re-runs re-enroll on their own when the enrolled key is not the plugged-in
# one (or was bound to another origin); 'reenroll' forces it. Remotely:
#   curl -fsSL https://raw.githubusercontent.com/hjbarraza/aerisos/main/titan/setup-titan-pam.sh | sudo bash
#
# Scope (deliberate):
#   - Only /etc/pam.d/hyprlock and /etc/pam.d/sddm get the U2F factor.
#   - tty login (Ctrl+Alt+F3) stays password-only as the recovery path
#     if the key is ever lost or broken.
#   - Unplugging the enrolled key terminates all of the user's sessions
#     via udev, then restarts SDDM (sddm-helper crashes on terminate-user
#     and the greeter is never respawned otherwise).
#   - The credential is bound to the fixed origin pam://aeris, not pamu2fcfg's
#     default pam://<hostname>, so renaming the machine does not lock you out.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

# The account to protect: the user who ran sudo
TARGET_USER="${SUDO_USER:-}"
[[ -n $TARGET_USER && $TARGET_USER != root ]] || { echo "run with sudo from your normal account, not as root" >&2; exit 1; }

REENROLL=0
[[ ${1:-} == reenroll ]] && REENROLL=1

ORIGIN=pam://aeris
U2F_LINE="auth        required    pam_u2f.so authfile=/etc/u2f_mappings origin=$ORIGIN appid=$ORIGIN cue"

echo "== 1/4 installing pam-u2f =="
pacman -S --needed --noconfirm pam-u2f    # pulls libfido2 (fido2-token)

echo "== 2/4 detecting the plugged-in security key =="
mapfile -t KEYS < <(fido2-token -L 2>/dev/null)
if (( ${#KEYS[@]} == 0 )); then
    echo "No FIDO2/U2F key found. Plug your key in and re-run." >&2
    exit 1
fi
if (( ${#KEYS[@]} > 1 )); then
    echo "Several keys are plugged in:"
    for i in "${!KEYS[@]}"; do printf '  %d) %s\n' "$((i+1))" "${KEYS[$i]}"; done
    read -rp "Which one guards the login? " N </dev/tty
    [[ $N =~ ^[0-9]+$ && $N -ge 1 && $N -le ${#KEYS[@]} ]] || { echo "invalid choice" >&2; exit 1; }
    KEY_LINE=${KEYS[$((N-1))]}
else
    KEY_LINE=${KEYS[0]}
fi
VID=$(sed -n 's/.*vendor=0x\([0-9a-fA-F]*\).*/\1/p' <<<"$KEY_LINE")
PID=$(sed -n 's/.*product=0x\([0-9a-fA-F]*\).*/\1/p' <<<"$KEY_LINE")
[[ -n $VID && -n $PID ]] || { echo "could not read the key's USB id from: $KEY_LINE" >&2; exit 1; }
# udev's PRODUCT is hex without leading zeros (kernel %x)
PRODUCT="$(printf '%x/%x' "0x$VID" "0x$PID")"
echo "key: $KEY_LINE  (udev PRODUCT $PRODUCT)"

KEY_DEV=${KEY_LINE%%:*}

# True if the plugged-in key holds a credential from /etc/u2f_mappings for
# $ORIGIN. Asks with up=false, so it needs no touch.
enrolled_key_matches() {
    local cred tmp
    tmp=$(mktemp)
    for cred in $(cut -d: -f2- /etc/u2f_mappings | tr ':' '\n' | cut -d, -f1); do
        printf '%s\n%s\n%s\n' "$(head -c32 /dev/urandom | base64)" "$ORIGIN" "$cred" > "$tmp"
        if fido2-assert -G -t up=false -i "$tmp" "$KEY_DEV" >/dev/null 2>&1; then
            rm -f "$tmp"; return 0
        fi
    done
    rm -f "$tmp"; return 1
}

if [[ -s /etc/u2f_mappings ]] && (( ! REENROLL )) && enrolled_key_matches; then
    echo "== 3/4 this key is already enrolled in /etc/u2f_mappings; keeping it =="
else
    echo "== 3/4 enrolling the key: TOUCH it when it blinks =="
    [[ -s /etc/u2f_mappings ]] && cp /etc/u2f_mappings "/etc/u2f_mappings.bak.$(date +%s)"
    # pamu2fcfg talks to the FIDO key and waits for a touch (and PIN, if one is set).
    pamu2fcfg -u "$TARGET_USER" -o "$ORIGIN" -i "$ORIGIN" > /etc/u2f_mappings.new
    # Public key handles only, not secrets; must be world-readable because
    # hyprlock runs PAM as the normal user.
    install -m 644 -o root -g root /etc/u2f_mappings.new /etc/u2f_mappings
    rm /etc/u2f_mappings.new
    echo "enrolled: $(cut -c1-40 /etc/u2f_mappings)..."
fi

echo "== patching PAM (hyprlock + sddm) =="
# An existing pam_u2f line (older installs had no origin) is replaced in place.
for f in /etc/pam.d/hyprlock /etc/pam.d/sddm; do
    sed -i "s|^auth.*pam_u2f\.so.*|$U2F_LINE|" "$f"
done
if ! grep -q pam_u2f /etc/pam.d/hyprlock; then
    sed -i "/^auth\s*include\s*login/a $U2F_LINE" /etc/pam.d/hyprlock
fi
if ! grep -q pam_u2f /etc/pam.d/sddm; then
    sed -i "/^auth\s*include\s*system-login/a $U2F_LINE" /etc/pam.d/sddm
fi
grep -H pam_u2f /etc/pam.d/hyprlock /etc/pam.d/sddm

echo "== 4/4 udev rule: log out $TARGET_USER when the key is unplugged =="
cat > /etc/udev/rules.d/90-titan-logout.rules <<EOF
# Security key ($KEY_LINE) removed -> end all of $TARGET_USER's sessions,
# then restart SDDM so the login screen comes back (sddm-helper crashes on
# terminate-user and the greeter is never respawned otherwise).
ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="$PRODUCT/*", RUN+="/usr/bin/sh -c '/usr/bin/loginctl terminate-user $TARGET_USER; /usr/bin/systemctl --no-block restart sddm'"
EOF
udevadm control --reload

echo
echo "DONE. Test NOW, before unplugging anything:"
echo "  1. Lock the screen. Unlock = type password, then touch the blinking key."
echo "  2. Only after that works, try unplugging the key: you should be logged out."
echo "Recovery if unlock ever fails: Ctrl+Alt+F3 tty login (password only)."

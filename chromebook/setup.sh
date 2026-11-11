#!/usr/bin/env bash
# AerisOS, Chromebook edition: the monochrome look on a 4 GB Chromebook.
#
# Start from EndeavourOS (Xfce) with this folder at ~/aerisos/chromebook, then:
#
#   ~/aerisos/chromebook/setup.sh
#
# Run it as your normal user in a real terminal: it calls sudo itself and asks
# for your password. Safe to re-run; every step skips work that is already done.
#
# What it does:
#   1. packages   everything in packages.txt
#   2. dotfiles   copies home/ into your home folder (Hyprland, bar, launcher, theme, scripts)
#   3. memory     compressed swap in RAM first, a small swap file on disk as the safety net
#   4. ssh        key-only login (skipped if you have no authorized key yet)
#   5. login      centred form on plain black, no wallpaper
#   6. boot       the tinyraven boot splash (Plymouth), quiet boot, menu renamed and hidden
#   7. services   Tailscale
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root." >&2; exit 1; }
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
log()  { printf '\n\033[1;37m■ %s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }

# Write a root-owned file only when its content changes. Usage: root_file PATH <<'EOF' ... EOF
root_file() {
    local path=$1 new; new=$(cat)
    if [[ "$(sudo cat "$path" 2>/dev/null)" == "$new" ]]; then info "unchanged: $path"; return 1; fi
    printf '%s\n' "$new" | sudo tee "$path" >/dev/null; info "wrote: $path"
}

log "Packages"
# shellcheck disable=SC2046
sudo pacman -S --needed --noconfirm $(grep -v '^#' "$HERE/packages.txt")

log "Dotfiles"
cp -rT "$HERE/home" "$HOME"
chmod +x "$HOME"/.local/bin/{aeris-battery,aeris-greeting,aeris-update,dnd,keybinds,make-mono-icons,power-menu,screenshot,stay-awake,tailscale-status} "$HOME/.config/hypr/find-window.py"
grep -q '\.local/bin' "$HOME/.bashrc" || printf '\n# User programs (helper scripts, Claude Code)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
# Terminal greeting in new kitty windows (not inside tmux, neovim's terminal or scripts).
grep -q aeris-greeting "$HOME/.bashrc" || cat >> "$HOME/.bashrc" <<'EOF'

# tinyraven greeting: new terminal windows only
[[ -n ${KITTY_WINDOW_ID:-} && -z ${TMUX:-} && -z ${NVIM:-} && -x ~/.local/bin/aeris-greeting ]] && ~/.local/bin/aeris-greeting
EOF
fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true
# Greyscale "Mono" icon theme, built from the installed app icons; re-run after installing apps.
"$HOME/.local/bin/make-mono-icons" >/dev/null && info "Mono icon theme built"
fc-list : family | grep '^Sohne' >/dev/null || info "! Söhne not found: copy your licensed Söhne files to ~/.local/share/fonts/soehne"
fc-list : family | grep '^Die Grotesk VF' >/dev/null || info "! Die Grotesk not found (the default interface font): copy DieGroteskVF-*.otf to ~/.local/share/fonts/die-grotesk"
fc-list : family | grep 'Symbols Nerd Font' >/dev/null || info "! Bar icons need Symbols Nerd Font in ~/.local/share/fonts"
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now aeris-battery.timer   # low-battery notices at 15% and 7%
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface icon-theme Mono
    gsettings set org.gnome.desktop.interface font-name 'Die Grotesk VF 10'
    gsettings set org.gnome.desktop.interface document-font-name 'Die Grotesk VF 10'
    gsettings set org.gnome.desktop.interface monospace-font-name 'Sohne Mono 10'
fi

log "Firefox: memory settings"
# user.js goes into every Firefox profile that exists; Firefox makes a profile at its first start.
shopt -s nullglob
for profile in "$HOME"/.config/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
    [[ -d $profile ]] || continue
    cmp -s "$HERE/firefox/user.js" "$profile/user.js" || { cp "$HERE/firefox/user.js" "$profile/user.js"; info "wrote: $profile/user.js (restart Firefox)"; }
done
shopt -u nullglob

log "Memory: compressed swap in RAM, then a swap file on disk"
# zram first (priority 100): fast, compresses about 3:1, so it may be as large as RAM.
if root_file /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
then info "zram resize takes effect at the next reboot"; fi
# Kernel settings recommended for zram swap (Arch wiki, "zram").
if root_file /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
then sudo sysctl --system >/dev/null; fi
# Swap file (priority 10): slow on an SD card, so it is only the net under zram.
# It keeps programs from being killed when memory runs out; it does not make the machine faster.
if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null
    info "created /swapfile (4 GB)"
fi
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab >/dev/null
[[ $(swapon --show=NAME --noheadings) == */swapfile* ]] || sudo swapon -p 10 /swapfile

log "SSH: key-only login"
if [[ -s $HOME/.ssh/authorized_keys ]]; then
    if root_file /etc/ssh/sshd_config.d/10-keys-only.conf <<'EOF'
# AerisOS: no password logins over SSH; use a key (ssh-copy-id from the other machine first).
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
    then sudo sshd -t && sudo systemctl reload sshd; fi
else
    info "! no key in ~/.ssh/authorized_keys yet; left password login on"
fi

log "Login screen: centred form on plain black"
# One [Greeter] section. EndeavourOS ships a wallpaper, a dot grid and a left-aligned form.
# An empty background= means no image, so background-color shows.
greeter=/etc/lightdm/slick-greeter.conf
# System-wide fonts: the login screen, root and any other user cannot see the fonts
# or the font defaults in your home folder. Same defaults as ~/.config/fontconfig/fonts.conf.
for family in die-grotesk soehne; do
    [[ -d $HOME/.local/share/fonts/$family && ! -d /usr/local/share/fonts/$family ]] || continue
    sudo mkdir -p /usr/local/share/fonts
    sudo cp -r "$HOME/.local/share/fonts/$family" /usr/local/share/fonts/
    sudo fc-cache -f /usr/local/share/fonts; info "installed system-wide: $family"
done
if ! sudo cmp -s "$HERE/home/.config/fontconfig/fonts.conf" /etc/fonts/local.conf; then
    sudo install -m644 "$HERE/home/.config/fontconfig/fonts.conf" /etc/fonts/local.conf
    info "wrote: /etc/fonts/local.conf (Die Grotesk and Söhne Mono as system defaults)"
fi
if [[ -f $greeter ]]; then
    for setting in content-align=center background= background-color=#000000 draw-grid=false 'font-name=Die Grotesk VF 10'; do
        grep -qxF "$setting" "$greeter" && continue
        sudo sed -i "/^${setting%%=*}=/d" "$greeter"
        echo "$setting" | sudo tee -a "$greeter" >/dev/null
        info "set $setting (shows at the next log out)"
    done
fi

log "Boot splash: tinyraven"
# The theme is built here, as the normal user, so the Söhne files in ~/.local/share/fonts
# are found: the splash, the light for the hairline, one strip per line of the phrases file, and
# the raven's frames (sway, blink, ruffle, dance). Plymouth shows one strip picked at random.
theme=/usr/share/plymouth/themes/tinyraven
tmp=$(mktemp -d)
rsvg-convert -w 1366 -b black "$HERE/splash.svg" -o "$tmp/bg.png"
rsvg-convert -w 560 -h 16 -o "$tmp/sweep.png" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 4"><defs><linearGradient id="g"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs><rect width="140" height="4" fill="url(#g)"/></svg>
EOF
phrases=0
while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    line=${line//&/"&amp;"}; line=${line//</"&lt;"}; line=${line//>/"&gt;"}
    # A full-width transparent strip with the text centred, for rows 488-512 of the splash.
    rsvg-convert -o "$tmp/phrase-$phrases.png" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1366" height="24" viewBox="0 0 1366 24"><text x="685" y="16" font-family="Söhne Mono, Sohne Mono" font-size="11" letter-spacing="4" fill="#b0b0b0" text-anchor="middle">$line</text></svg>
EOF
    phrases=$((phrases + 1))
done < "$HERE/home/.config/tinyraven/phrases.txt"
(( phrases > 0 )) || { echo "phrases.txt has no phrases" >&2; exit 1; }
# The raven's frames, in a 280x224 box at (543,168) of the splash. mask.png hides the still bird.
# raven_frame FILE TURN EYE PUFF BACK_LIFT FRONT_LIFT DROP
#   TURN   body turn in degrees about the feet     EYE    open or shut
#   PUFF   0 to 1, body fluffed up                 LIFTs  each foot's height off the ground
#   DROP   body shift down (negative is up)
# The legs are drawn first and do not turn, so the feet stay planted while the body sways.
raven_frame() {
    local out=$1 turn=$2 eye=$3 puff=$4 back=$5 front=$6 drop=$7 pupil= grow legs
    [[ $eye == open ]] && pupil='<circle cx="138" cy="62" r="4" fill="#000"/>'
    grow=$(awk -v a="$puff" 'BEGIN { printf "%.4f,%.4f", 1 + 0.05 * a, 1 + 0.02 * a }')
    legs=$(awk -v b="$back" -v f="$front" -v d="$drop" 'BEGIN {
        printf "M96,%.1f V%.1f M92,%.1f H105 M114,%.1f V%.1f M110,%.1f H123", 158 + d, 189 - b, 189 - b, 152 + d, 189 - f, 189 - f }')
    rsvg-convert -o "$out" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="280" height="224" viewBox="0 0 280 224"><g transform="translate(19.3,-28.8) scale(1.2)"><path d="$legs" stroke="#fff" stroke-width="3.2" stroke-linecap="round" fill="none"/><g transform="translate(0,$drop) rotate($turn 100 172) translate(100,125) scale($grow) translate(-100,-125)"><path fill="#fff" d="M186,74 C172,62 160,52 146,48 C128,40 110,46 102,62 C88,84 66,112 48,142 C36,160 22,178 10,192 C30,186 46,178 60,170 C80,170 100,168 116,158 C136,146 148,124 150,100 C151,90 156,82 162,80 C170,78 178,76 186,74 Z"/>$pupil</g></g></svg>
EOF
}
# Sway: 13 angles from -1.2 to +1.2 degrees, each with the eye open and shut.
for i in {0..12}; do
    angle=$(awk -v i="$i" 'BEGIN { printf "%.1f", (i - 6) * 0.2 }')
    raven_frame "$tmp/bird-$i.png"       "$angle" open 0 0 0 0
    raven_frame "$tmp/bird-$i-blink.png" "$angle" shut 0 0 0 0
done
# The lock screen shows the same bird, upright and still.
raven_frame "$HOME/.config/hypr/raven.png" 0 open 0 0 0 0
# Ruffle: puff up, a quick shake, settle. Each step: "puff shake".
n=0
for step in "0.3 0" "0.7 -0.6" "1 0.8" "1 -0.8" "1 0.8" "0.9 -0.6" "0.7 0.4" "0.5 -0.2" "0.3 0" "0.15 0" "0.05 0"; do
    read -r puff shake <<<"$step"
    raven_frame "$tmp/bird-ruffle-$n.png" "$shake" open "$puff" 0 0 0; n=$((n + 1))
done
# Dance: stomp back foot, front foot, twice over, then one small hop and a landing.
# Each step: "back-lift front-lift drop turn".
n=0
for step in "6 0 0 -1.5" "0 0 1.5 -0.5" "0 6 0 1.5" "0 0 1.5 0.5" "6 0 0 -1.5" "0 0 1.5 -0.5" "0 6 0 1.5" "0 0 1.5 0.5" "5 5 -4 0" "0 0 2.5 0" "0 0 0.8 0"; do
    read -r back front drop turn <<<"$step"
    raven_frame "$tmp/bird-dance-$n.png" "$turn" open 0 "$back" "$front" "$drop"; n=$((n + 1))
done
rsvg-convert -o "$tmp/mask.png" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="280" height="224"><rect width="280" height="224" fill="#000"/></svg>
EOF
cp "$HERE/plymouth/tinyraven.plymouth" "$tmp/"
sed "s/@PHRASES@/$phrases/" "$HERE/plymouth/tinyraven.script" > "$tmp/tinyraven.script"
# theme built
rebuild=0
if ! diff -rq "$tmp" "$theme" >/dev/null 2>&1; then
    sudo rm -rf "$theme"; sudo mkdir -p "$theme"
    sudo install -m644 -t "$theme" "$tmp"/*
    info "installed: $theme ($phrases phrases)"; rebuild=1
fi
rm -rf "$tmp"
if root_file /etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=tinyraven
ShowDelay=0
DeviceScale=1
EOF
then rebuild=1; fi
# Quiet boot: without it the kernel prints over the splash.
cmdline=/etc/kernel/cmdline
[[ -f $cmdline.bak ]] || sudo cp "$cmdline" "$cmdline.bak"
for arg in quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0; do
    grep -qw -- "$arg" "$cmdline" && continue
    sudo sed -i "s|\$| $arg|" "$cmdline"; info "kernel option: $arg"; rebuild=1
done
# Boot menu: entries named "AerisOS TinyRaven" (a kernel-install hook renames them each
# time they are written), and the menu hidden. Hold Space at boot to show it.
hook=/etc/kernel/install.d/95-aeris-title.install
if ! sudo cmp -s "$HERE/boot/95-aeris-title.install" "$hook"; then
    sudo install -Dm755 "$HERE/boot/95-aeris-title.install" "$hook"; info "installed: $hook"; rebuild=1
fi
loader=/efi/loader/loader.conf
if ! sudo grep -q '^timeout 0$' "$loader"; then
    if sudo grep -q '^timeout' "$loader"; then sudo sed -i 's/^timeout.*/timeout 0/' "$loader"
    else echo 'timeout 0' | sudo tee -a "$loader" >/dev/null; fi
    info "boot menu hidden (timeout 0 in $loader)"
fi
# EndeavourOS: rebuilds the boot image (dracut) and the boot entries with the new options.
if (( rebuild )); then sudo reinstall-kernels; info "boot image rebuilt; the splash shows at the next boot"; fi

log "Services"
sudo systemctl enable --now tailscaled
tailscale status >/dev/null 2>&1 || info "! Tailscale is not logged in: sudo tailscale up"

log "Done"
info "Log out and in (or reboot) to load the lock screen and idle rules."
command -v claude >/dev/null || info "Claude Code: curl -fsSL https://claude.ai/install.sh | bash"

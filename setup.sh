#!/bin/bash
# AerisOS setup: turns a fresh Arch Linux + Hyprland install into AerisOS.
#
# Usage: ./setup.sh [--dry-run] [module ...]
#        ./setup.sh               run every install module (same as "all")
#        ./setup.sh steam boot    run only these modules
#        ./setup.sh essentials    Brave, w3m and Claude Code only (runs first in a full install)
#        ./setup.sh wizard        (re-)answer the personal questions (name, email, hostname, maps)
#        ./setup.sh maps          install/update the defence-maps app (separate private repo)
#        ./setup.sh gamesdrive    optional: mount this laptop's games drive
#        ./setup.sh razer         optional: Razer laptop control + battery held at 90-95%
#        ./setup.sh titan         security key 2FA for lock/login + logout on unplug
#                                 (optional, wizard asks; Titan, YubiKey or any FIDO2 key)
#        ./setup.sh snapshot      save this machine's configs + package lists into the repo
#        ./setup.sh --list        list modules
#
# New machine from scratch (minimal Arch, as root): see install.sh
#
# Run as your normal user in a real terminal (it asks for your sudo password).
# Safe to re-run: every step skips work that's already done. See README.md.

set -euo pipefail

AERIS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DOT="$AERIS/dotfiles"
PKG="$AERIS/packages"
BACKUP="$HOME/.local/state/aerisos/backup-$(date +%Y%m%d-%H%M%S)"
OS_NAME="AerisOS"   # ASCII: firmware boot menus often can't draw Æ
DRY=0
WIZARD_FORCED=0
MAPS_FORCED=0
TITAN_FORCED=0

# Personal answers from the wizard (name, email, maps repo); survives re-runs
CONF="$HOME/.config/aerisos/setup.conf"
# shellcheck disable=SC1090
[[ -f $CONF ]] && source "$CONF"

# Install modules, in the order "all" runs them
MODULES=(t2 essentials wizard packages hardware steam controller dotfiles login voxtype tools omacom aeris tts maps titan theme safety boot logins)
# Only run when named: hardware unique to one machine, or maintenance
OPTIONAL=(gamesdrive razer snapshot)

# Configs captured by "snapshot" and restored by "dotfiles" (relative to $HOME).
# Commands are not here: they live in bin/ and are installed by the tools module.
HOME_PATHS=(
    .bashrc
    .config/hypr
    .config/quickshell
    .config/ghostty
    .config/kitty
    .config/dunst
    .config/swayosd
    .config/gtk-3.0
    .config/gtk-4.0
    .config/mimeapps.list
    .config/voxtype/config.toml
    .config/vicinae/settings.json
    .local/share/vicinae/themes
    .local/share/fonts
    .config/autostart/nm-applet.desktop
    .config/omarchy/themes
    .local/share/aeris/watchlist.json
    .config/opencode
    .config/systemd/user/aeris-watch.service
    .config/systemd/user/aeris-watch.timer
    .config/systemd/user/aeris-watch.service.d
    .config/systemd/user/aeris-announce.service
    .config/systemd/user/defence-maps.service
    .claude/skills
    .claude/settings.json
    AGENTS.md
)
# System files captured by "snapshot" and restored by "login"
SYSTEM_PATHS=(
    /etc/sddm.conf.d/10-theme.conf
    /usr/share/sddm/themes/monochrome
)
# Never snapshot editor/backup leftovers
EXCLUDES=(--exclude='*.bak' --exclude='*.bak[0-9]*' --exclude='*.bak-*' --exclude='*.pre-*' --exclude='*.orig'
          --exclude='__pycache__' --exclude='node_modules')

# --- helpers -----------------------------------------------------------------

log()  { printf '\n\033[1;37m■ %s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  \033[1;33m! %s\033[0m\n' "$*" >&2; }

# Run a state-changing command (printed instead when --dry-run)
run() {
    if (( DRY )); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}
as_root() { run sudo "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Only call sudo when something is actually missing
pacman_install() {
    local missing
    missing=$(pacman -T "$@" || true)
    [[ -z $missing ]] && return 0
    # shellcheck disable=SC2086
    as_root pacman -S --needed --noconfirm $missing
}

aur_install() {
    have yay || { warn "yay missing; run the 'packages' module first"; return 1; }
    local missing
    missing=$(pacman -T "$@" || true)
    [[ -z $missing ]] && return 0
    # shellcheck disable=SC2086
    run yay -S --needed --noconfirm $missing
}

# Write stdin to a root-owned file (shown instead when --dry-run)
write_root_file() {
    local path=$1 content
    content=$(cat)
    if (( DRY )); then info "[dry-run] write $path"; return; fi
    sudo mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" | sudo tee "$path" >/dev/null
}

# (grep without -q: an early exit would SIGPIPE the producer and trip pipefail)
gpu_has() { lspci | grep -iE 'vga|3d|display' | grep -iE "$1" >/dev/null; }

# Local model for the lock screen and watchlist: CUDA + qwen3.5:9b on NVIDIA; anything
# else (the T2 Mac's Radeon 5500M: no ROCm, 4 GB) gets Vulkan + qwen3.5:4b, the largest
# that leaves room for voxtype. OpenCode needs more than that: OpenRouter there
llm_model() { if gpu_has nvidia; then echo qwen3.5:9b; else echo qwen3.5:4b; fi; }

# Intel Mac with the T2 chip (needs the linux-t2 kernel from the arch-mact2 repo)
is_t2() { lspci | grep -i 'T2 Bridge' >/dev/null; }

# PCI address of the first GPU matching a vendor, e.g. "0000:01:00.0"
gpu_addr() { lspci -D | grep -iE 'vga|3d|display' | grep -iE "$1" | head -1 | cut -d' ' -f1; }

# "0000:01:00.0" -> "PCI:1:0:0" (Xorg wants decimal bus:device:function)
xorg_busid() {
    local a=${1#*:}
    printf 'PCI:%d:%d:%d' "0x${a%%:*}" "0x$(cut -d: -f2 <<<"$a" | cut -d. -f1)" "0x${a##*.}"
}

# Set key=value in a GTK settings.ini (creates the file/section if needed)
gtk_ini_set() {
    local ini=$1 key=$2 val=$3
    if (( DRY )); then info "[dry-run] $ini: $key=$val"; return; fi
    mkdir -p "$(dirname "$ini")"
    [[ -f $ini ]] || printf '[Settings]\n' > "$ini"
    if grep -q "^$key=" "$ini"; then
        sed -i "s|^$key=.*|$key=$val|" "$ini"
    else
        sed -i "/^\[Settings\]/a $key=$val" "$ini"
    fi
}

# Native resolution of the built-in (or first connected) display, e.g. "2560 1440"
native_res() {
    local f
    for f in /sys/class/drm/card*-eDP-*/modes /sys/class/drm/card*-*/modes; do
        if [[ -s $f && $(cat "${f%modes}status") == connected ]]; then
            head -1 "$f" | tr x ' '
            return
        fi
    done
    echo "1920 1080"
}

# Render the brand assets from splash.svg into $1, sized to fill the screen:
#   splash.bmp            still boot splash (systemd-stub needs a 24-bit BMP)
#   bg.png, sweep.png     Plymouth layers (static background + the light that sweeps the rule)
build_brand() {
    local out=$1 w h sw
    read -r w h < <(native_res)
    # Largest 16:9 size that fits: full screen on 16:9 panels, never bigger than the screen
    sw=$(( w * 900 <= h * 1600 ? w : h * 1600 / 900 ))
    mkdir -p "$out"
    have rsvg-convert || pacman_install librsvg

    rsvg-convert -w "$sw" -a -b black "$AERIS/splash.svg" -o "$out/splash.png"
    if have magick; then
        magick "$out/splash.png" -type truecolor "BMP3:$out/splash.bmp"
    else
        python3 -I "$AERIS/png2bmp.py" "$out/splash.png" "$out/splash.bmp"
    fi

    cp "$out/splash.png" "$out/bg.png"
    cat > "$out/sweep.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 4"><defs><linearGradient id="g"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs><rect width="140" height="4" fill="url(#g)"/></svg>
EOF
    rsvg-convert -w 560 -h 16 "$out/sweep.svg" -o "$out/sweep.png"
}

# --- modules -------------------------------------------------------------------

# T2 Macs only (skipped elsewhere). The kernel, firmware and boot entry come from
# t2/chroot.sh at install time; this keeps them updatable and the repos sane
mod_t2() {
    is_t2 || return 0
    log "T2 Mac: arch-mact2 repo, linux-t2 kernel, stable repos only, internal NIC ignored"
    if [[ ! -s /etc/pacman.d/arch-mact2-mirrorlist ]]; then
        write_root_file /etc/pacman.d/arch-mact2-mirrorlist < "$AERIS/t2/arch-mact2-mirrorlist"
    fi
    if ! grep -q '^\[arch-mact2\]' /etc/pacman.conf; then
        info "Adding the arch-mact2 repo (linux-t2 updates come from it)"
        as_root sh -c "printf '\n[arch-mact2]\nInclude = /etc/pacman.d/arch-mact2-mirrorlist\nSigLevel = Never\n' >> /etc/pacman.conf"
    fi
    # Testing repos only by accident: AerisOS is built on stable packages
    if grep -qE '^\[(core|extra|multilib)-testing\]' /etc/pacman.conf; then
        warn "Testing repos were enabled in /etc/pacman.conf; turning them off"
        as_root sed -i -E '/^\[(core|extra|multilib)-testing\]/{s/^/#/;n;s/^/#/}' /etc/pacman.conf
    fi
    as_root pacman -Sy
    pacman_install linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware-fetcher iwd

    # The T2's internal USB ethernet (iBridge, same MAC on every T2 Mac) never gets an
    # address; without this NetworkManager shows it "connecting" forever
    if [[ ! -f /etc/NetworkManager/conf.d/t2-ibridge.conf ]]; then
        printf '[keyfile]\nunmanaged-devices=mac:ac:de:48:00:11:22\n' \
            | write_root_file /etc/NetworkManager/conf.d/t2-ibridge.conf
        as_root nmcli general reload || true
    fi
}

# First, and never fatal: a browser, a terminal browser and Claude Code are there
# to get help even if a later module breaks
mod_essentials() {
    log "Essentials: Brave, w3m (terminal browser), Claude Code"
    pacman_install w3m flatpak || warn "w3m/flatpak install failed"

    # Brave from Flathub (no AUR build to fail); /usr/local/bin/brave because
    # hyprland.lua and the web apps call it by name
    as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    as_root flatpak install -y --noninteractive flathub com.brave.Browser || warn "Brave flatpak install failed; re-run: ./setup.sh essentials"
    if [[ ! -x /usr/local/bin/brave ]]; then
        printf '#!/bin/sh\nexec flatpak run com.brave.Browser "$@"\n' | write_root_file /usr/local/bin/brave
        as_root chmod 755 /usr/local/bin/brave
    fi

    # Claude Code (native installer, into ~/.local/bin). The dotfiles .bashrc puts that on
    # PATH later; until then, add it so `claude` works in the next terminal
    if [[ ! -x $HOME/.local/bin/claude ]]; then
        run bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || warn "Claude Code install failed; re-run: ./setup.sh essentials"
    fi
    if ! grep -qs '\.local/bin' "$HOME/.bashrc"; then
        run sh -c "printf '%s\n' 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> \"\$HOME/.bashrc\""
    fi
    info "Browser: brave (or w3m in a terminal). Help: open a new terminal and run claude"
}

mod_packages() {
    log "Packages: multilib, system update, yay, package lists"

    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        info "Enabling multilib (backup: /etc/pacman.conf.bak)"
        as_root cp /etc/pacman.conf /etc/pacman.conf.bak
        as_root sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    fi
    as_root pacman -Syu --noconfirm
    pacman_install base-devel git

    # AUR builds without -debug packages: the binary ones have no symbols (a screen of
    # errors per package) and the rest aren't worth a second package each
    if ! grep -qs '^OPTIONS+=(!debug)' "$HOME/.config/pacman/makepkg.conf"; then
        run mkdir -p "$HOME/.config/pacman"
        run sh -c "echo 'OPTIONS+=(!debug)' >> \"\$HOME/.config/pacman/makepkg.conf\""
    fi
    local debug; debug=$(pacman -Qqm | grep -- '-debug$' || true)
    # shellcheck disable=SC2086
    [[ -z $debug ]] || as_root pacman -Rns --noconfirm $debug

    if ! have yay; then
        info "Bootstrapping yay from the AUR"
        local tmp; tmp=$(mktemp -d)
        run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi

    if [[ -s $PKG/pacman.txt ]]; then
        # Skip anything no longer in the repos instead of failing the whole install
        local available wanted missing
        available=$(pacman -Slq | sort -u)
        wanted=$(comm -12 <(sort -u "$PKG/pacman.txt") <(echo "$available"))
        missing=$(comm -23 <(sort -u "$PKG/pacman.txt") <(echo "$available"))
        [[ -n $missing ]] && warn "Not in repos, skipped: $(echo $missing)"
        # NVIDIA drivers, CUDA and local models only where there's an NVIDIA GPU
        if ! gpu_has nvidia; then
            wanted=$(grep -vE '^(lib32-)?nvidia|^libva-nvidia|^ollama-cuda$|^steam$' <<<"$wanted" || true)
            info "No NVIDIA GPU: skipping NVIDIA drivers, CUDA and Steam"
        fi
        # shellcheck disable=SC2086
        pacman_install $wanted
    fi
    if [[ -s $PKG/aur.txt ]]; then
        # shellcheck disable=SC2046
        aur_install $(grep -vE '^(yay-bin|.*-debug)$' "$PKG/aur.txt" | { gpu_has nvidia && cat || grep -vx envycontrol; })
    fi
}

mod_hardware() {
    log "Hardware: GPU drivers, stable GPU names, early graphics, laptop fixes"
    local rebuild=0

    # hyprpolkitagent handles password prompts; the KDE agent would double up
    if pacman -Q polkit-kde-agent >/dev/null 2>&1; then
        as_root pacman -Rns --noconfirm polkit-kde-agent
    fi

    if gpu_has nvidia; then
        pacman_install nvidia-open nvidia-utils nvidia-prime nvidia-settings egl-wayland libva-nvidia-driver
        # Keep nouveau out of the initramfs: the kms hook pulls it in
        if grep -qE '^HOOKS=.*[ (]kms[ )]' /etc/mkinitcpio.conf; then
            as_root sed -i -E '/^HOOKS=/ s/ kms / /' /etc/mkinitcpio.conf
            rebuild=1
        fi
        as_root systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
        # GPU mode switching (integrated / hybrid / nvidia); also in the AerisOS menu
        aur_install envycontrol
    fi

    # Early KMS for the Intel iGPU: i915 in the initramfs so Plymouth draws on it from the
    # start (loaded late, i915 inherits the firmware framebuffer and the vendor logo reappears)
    if gpu_has intel && ! grep -qE '^MODULES=\(.*\bi915\b' /etc/mkinitcpio.conf; then
        as_root sed -i -E 's/^MODULES=\((.*)\)/MODULES=(\1 i915)/; s/^MODULES=\( i915\)/MODULES=(i915)/' /etc/mkinitcpio.conf
        rebuild=1
    fi

    # Stable /dev/dri names for Hyprland (card0/card1 can swap between boots)
    local intel nvidia rules=""
    intel=$(gpu_addr intel || true)
    nvidia=$(gpu_addr nvidia || true)
    [[ -n $intel  ]] && rules+="KERNEL==\"card*\", SUBSYSTEM==\"drm\", KERNELS==\"$intel\", SYMLINK+=\"dri/intel-igpu\""$'\n'
    [[ -n $nvidia ]] && rules+="KERNEL==\"card*\", SUBSYSTEM==\"drm\", KERNELS==\"$nvidia\", SYMLINK+=\"dri/nvidia-dgpu\""$'\n'
    if [[ -n $rules ]]; then
        printf '%s' "$rules" | write_root_file /etc/udev/rules.d/99-dri-names.rules
    fi

    # Built-in microphone on the Razer Blade 17 (2022): empty BIOS NHLT table
    # means the kernel picks a topology without the DMIC array
    if [[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == "Blade 17 (2022)"* ]]; then
        if [[ ! -f /etc/modprobe.d/sof.conf ]]; then
            write_root_file /etc/modprobe.d/sof.conf <<'EOF'
# Workaround for empty BIOS NHLT on Razer Blade 17 (2022): without these the
# kernel loads sof-hda-generic-2ch.tplg and the built-in mic records silence.
options snd_sof tplg_filename=sof-hda-generic-2ch-pdm1.tplg
options snd_sof_intel_hda_common sof_use_tplg_nhlt=1
EOF
            rebuild=1
        fi
    fi

    (( rebuild )) && as_root mkinitcpio -P
    info "Reboot after this module for driver changes to take effect"
}

mod_steam() {
    log "Steam + 32-bit graphics drivers"
    if ! gpu_has nvidia; then
        info "No NVIDIA GPU: Steam skipped (gaming machines only)"
        return 0
    fi
    grep -q '^\[multilib\]' /etc/pacman.conf || { warn "multilib is off; run the 'packages' module first"; return 1; }

    local pkgs=(steam ttf-liberation)
    gpu_has intel      && pkgs+=(vulkan-intel lib32-vulkan-intel lib32-mesa)
    gpu_has 'amd|ati'  && pkgs+=(vulkan-radeon lib32-vulkan-radeon lib32-mesa)
    gpu_has nvidia     && pkgs+=(nvidia-utils lib32-nvidia-utils nvidia-prime)
    pacman_install "${pkgs[@]}"
    info "Run Steam on the NVIDIA GPU with: prime-run steam"
}

mod_controller() {
    log "Xbox controller: USB (built in), Bluetooth (xpadneo), wireless dongle (xone)"
    pacman_install bluez bluez-utils dkms linux-headers
    as_root systemctl enable --now bluetooth.service
    aur_install xpadneo-dkms xone-dkms
    aur_install xone-dongle-firmware || warn "Dongle firmware failed; if the dongle LED stays off run: sudo xone-get-firmware.sh"
    # Steam Input uses uinput
    if [[ ! -f /etc/modules-load.d/uinput.conf ]]; then
        echo uinput | write_root_file /etc/modules-load.d/uinput.conf
        as_root modprobe uinput || true
    fi
}

# Re-mount the games drive (btrfs labelled "games", created by games-drive.sh) without formatting it
mod_gamesdrive() {
    log "Games drive: mount LABEL=games at /mnt/games on every boot"
    if ! blkid -L games >/dev/null 2>&1; then
        warn "No drive labelled 'games' found; to create one (ERASES the drive) see games-drive.sh"
        return 0
    fi
    if ! grep -qE '^LABEL=games[[:space:]]|[[:space:]]/mnt/games[[:space:]]' /etc/fstab; then
        if (( DRY )); then info "[dry-run] add LABEL=games to /etc/fstab"
        else
            sudo cp -n /etc/fstab /etc/fstab.bak
            printf '\n# Games drive. nofail: boot continues if the drive is missing.\nLABEL=games\t/mnt/games\tbtrfs\trw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,nofail,x-systemd.device-timeout=10s,x-gvfs-show,x-gvfs-name=Games\t0 0\n' \
                | sudo tee -a /etc/fstab >/dev/null
        fi
    fi
    as_root mkdir -p /mnt/games
    as_root systemctl daemon-reload
    findmnt /mnt/games >/dev/null || as_root mount /mnt/games
    as_root chown "$USER:$USER" /mnt/games
    info "In Steam: Settings > Storage > Add Drive > /mnt/games/SteamLibrary"
}

mod_dotfiles() {
    log "Dotfiles: restoring configs (existing files backed up to $BACKUP)"
    [[ -d $DOT/home ]] || { warn "No snapshot in $DOT; run './setup.sh snapshot' on a configured machine"; return 1; }

    # Back up whatever is about to be overwritten
    local rel
    for rel in "${HOME_PATHS[@]}"; do
        [[ -e $DOT/home/$rel && -e $HOME/$rel ]] || continue
        run mkdir -p "$BACKUP/$(dirname "$rel")"
        run cp -a "$HOME/$rel" "$BACKUP/$rel"
    done
    run cp -a "$DOT/home/." "$HOME/"
    run fc-cache -f >/dev/null

    # Folders open in Files (Nautilus), not a terminal
    have nautilus && run xdg-mime default org.gnome.Nautilus.desktop inode/directory

    if ! fc-list : family | grep 'Söhne' >/dev/null; then
        warn "Söhne font not found: copy your licensed Söhne files to ~/.local/share/fonts/soehne"
    fi
}

mod_login() {
    log "Login screen: SDDM with the AerisOS theme (splash layout, live info, animated)"
    pacman_install sddm

    # The greeter runs as the sddm user, so Söhne must be installed system-wide
    if [[ -d $HOME/.local/share/fonts/soehne ]]; then
        as_root mkdir -p /usr/local/share/fonts
        as_root cp -r "$HOME/.local/share/fonts/soehne" /usr/local/share/fonts/
        as_root fc-cache -f /usr/local/share/fonts
    else
        warn "Söhne not in ~/.local/share/fonts/soehne; the login screen will fall back to another font"
    fi

    # Japanese type for the kanji accents; checkupdates for the pending-updates count
    pacman_install adobe-source-han-sans-jp-fonts pacman-contrib

    as_root rm -rf /usr/share/sddm/themes/aeris
    as_root cp -r "$AERIS/sddm/aeris" /usr/share/sddm/themes/aeris
    as_root chown -R root:root /usr/share/sddm/themes/aeris

    # Live info: aeris-status writes /var/lib/aeris/status.json at boot and every minute
    as_root install -m755 "$AERIS/status/aeris-status" /usr/local/bin/aeris-status
    # Older versions cached the public IP in this world-readable file; it now goes to private.json
    as_root rm -f /var/lib/aeris/net-cache.json
    sed "s/^Environment=AERIS_USER=.*/Environment=AERIS_USER=$USER/" "$AERIS/status/aeris-status.service" \
        | write_root_file /etc/systemd/system/aeris-status.service
    as_root install -m644 "$AERIS/status/aeris-status.timer" /etc/systemd/system/aeris-status.timer
    as_root systemctl daemon-reload
    as_root systemctl enable --now aeris-status.timer

    # Monochrome theme stays installed as a fallback
    if [[ -d $DOT/system/usr/share/sddm/themes/monochrome ]]; then
        as_root rm -rf /usr/share/sddm/themes/monochrome
        as_root cp -a "$DOT/system/usr/share/sddm/themes/monochrome" /usr/share/sddm/themes/
        as_root chown -R root:root /usr/share/sddm/themes/monochrome
    fi
    if [[ -f $DOT/system/etc/sddm.conf.d/10-theme.conf ]]; then
        as_root install -Dm644 "$DOT/system/etc/sddm.conf.d/10-theme.conf" /etc/sddm.conf.d/10-theme.conf
    fi
    if [[ -f /etc/sddm.conf.d/10-theme.conf ]] || (( DRY )); then
        as_root sed -i 's/^Current=.*/Current=aeris/' /etc/sddm.conf.d/10-theme.conf
    else
        printf '[Theme]\nCurrent=aeris\n' | write_root_file /etc/sddm.conf.d/10-theme.conf
    fi
    # The theme reads the status file through QML's XMLHttpRequest, which needs this switch
    if (( DRY )); then info "[dry-run] allow the greeter to read the status file"
    elif ! grep -q QML_XHR_ALLOW_FILE_READ /etc/sddm.conf.d/10-theme.conf; then
        if grep -q '^GreeterEnvironment=' /etc/sddm.conf.d/10-theme.conf; then
            sudo sed -i 's/^GreeterEnvironment=.*/&,QML_XHR_ALLOW_FILE_READ=1/' /etc/sddm.conf.d/10-theme.conf
        else
            printf '\n[General]\nGreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1\n' | sudo tee -a /etc/sddm.conf.d/10-theme.conf >/dev/null
        fi
    fi

    # Hybrid laptops: pin the X11 greeter to the Intel iGPU (NVIDIA gives a black screen)
    if gpu_has intel && gpu_has nvidia; then
        write_root_file /etc/X11/xorg.conf.d/10-intel-primary.conf <<EOF
Section "ServerFlags"
    Option "AutoAddGPU"  "off"
    Option "AutoBindGPU" "off"
EndSection

Section "Device"
    Identifier "Intel iGPU"
    Driver     "modesetting"
    BusID      "$(xorg_busid "$(gpu_addr intel)")"
EndSection
EOF
    fi
    as_root systemctl enable sddm.service
    info "Shows at next logout/reboot (restarting sddm from the desktop logs you out)"
}

mod_voxtype() {
    log "Voxtype dictation: install, speech model, GPU, top-bar icon only"
    pacman_install wtype libnotify
    aur_install voxtype-bin
    run voxtype setup --download --model small.en --quiet || warn "Model download failed; run: voxtype setup model"
    if ! voxtype setup gpu --status 2>/dev/null | grep 'Active backend: GPU' >/dev/null; then
        as_root voxtype setup gpu --enable || warn "GPU acceleration failed; Voxtype still works on the CPU"
    fi
    # No floating overlay: status lives in the Quickshell bar icon (right of the clock)
    run voxtype config set osd.enabled false
    run systemctl --user enable voxtype.service
    run systemctl --user restart voxtype.service
    info "Dictate: hold Right Option/Alt (or Right Ctrl), speak, release (bound in hyprland.lua)"
}

mod_tools() {
    log "Tools: AerisOS menu, update, battery alerts, web apps, codecs, Node + Git"
    run mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/systemd/user"

    # Every AerisOS command (bin/, see docs/commands.md): the menu, update, toggles, capture,
    # the watchlist tools, the voice, the bar and lock-screen helpers, and the `aeris` router
    # that lists them. Keybinds live in hyprland.lua
    local cmd
    for cmd in "$AERIS"/bin/*; do
        [[ -f $cmd && -x $cmd ]] && run install -m755 "$cmd" "$HOME/.local/bin/"
    done
    # Lock screen: generated from the login screen's grid (lock/make-hyprlock).
    # hypridle listens for loginctl lock-session (CTRL+L, screen-off, suspend) and
    # runs hyprlock — without it the lock binds do nothing.
    run python3 "$AERIS/lock/make-hyprlock" "$HOME/.config/hypr/hyprlock.conf"
    run systemctl --user enable --now hypridle.service
    run install -m644 "$AERIS/battery/aeris-battery.service" "$AERIS/battery/aeris-battery.timer" "$HOME/.config/systemd/user/"
    run systemctl --user daemon-reload
    run systemctl --user enable --now aeris-battery.timer

    # The menu's UI: a Vicinae extension (vicinae/aerisos) with sections, icons and live state,
    # built into ~/.local/share/vicinae/extensions (node_modules removed afterwards)
    if have vicinae; then
        if (( DRY )); then info "[dry-run] build the AerisOS Vicinae extension"
        else
            (cd "$AERIS/vicinae/aerisos" && npm install --no-audit --no-fund --silent && npx vici build && rm -rf node_modules)
            pgrep -x vicinae >/dev/null && (setsid vicinae server --replace >/dev/null 2>&1 &)
        fi
    fi

    # Web apps: each site in its own Brave window, in the launcher (SUPER+SHIFT+C/Y/I/G//)
    run install -m644 "$AERIS"/webapps/*.desktop "$HOME/.local/share/applications/"

    # Brave: AERIS monochrome theme, staged where the Flatpak sandbox can read it.
    # One-time manual step: brave://extensions → Developer mode → Load unpacked → this folder.
    if [[ -d $HOME/.var/app/com.brave.Browser ]]; then
        run mkdir -p "$HOME/.var/app/com.brave.Browser/aeris-theme"
        run install -m644 "$AERIS/brave-theme/manifest.json" "$HOME/.var/app/com.brave.Browser/aeris-theme/"
        info "Brave theme: brave://extensions → Developer mode → Load unpacked → ~/.var/app/com.brave.Browser/aeris-theme"
    fi

    # Media codecs for every app (GStreamer) and Files thumbnails
    pacman_install gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg ffmpegthumbnailer

    # Flatpak apps: LocalSend (file drops between machines; firewall port opened by `safety`)
    pacman_install flatpak
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    run flatpak install -y --user flathub org.localsend.localsend_app || warn "LocalSend flatpak install failed; run it again later"
    # Launchers only see flatpak apps once XDG_DATA_DIRS includes the export dir (next login).
    # A copy in ~/.local/share/applications is visible immediately, shadows the export after
    # re-login (same desktop id), and swaps the icon for a themed one: LocalSend's own icon
    # only ships at 512px, which Vicinae won't scale (shows "?").
    run mkdir -p "$HOME/.local/share/applications"
    if [[ -f $HOME/.local/share/flatpak/exports/share/applications/org.localsend.localsend_app.desktop ]]; then
        sed 's/^Icon=.*/Icon=document-send/' \
            "$HOME/.local/share/flatpak/exports/share/applications/org.localsend.localsend_app.desktop" \
            > "$HOME/.local/share/applications/org.localsend.localsend_app.desktop"
    fi

    # Node: global npm packages go to ~/.local (no sudo). Git defaults; GitHub via gh
    pacman_install nodejs npm git github-cli
    run npm config set prefix "$HOME/.local"
    run git config --global init.defaultBranch main
    run git config --global push.autoSetupRemote true
    run git config --global pull.rebase false
    if [[ -n ${AERIS_GIT_EMAIL:-} ]]; then run git config --global user.email "$AERIS_GIT_EMAIL"; fi
    if [[ -n ${AERIS_GIT_NAME:-} ]]; then run git config --global user.name "$AERIS_GIT_NAME"; fi
    gh auth status >/dev/null 2>&1 || info "GitHub: the 'logins' module at the end runs 'gh auth login'"
}

mod_logins() {
    log "Logins: GitHub and Tailscale (interactive, browser flows; safe to re-run)"
    if gh auth status >/dev/null 2>&1; then
        info "GitHub: already logged in"
    else
        run gh auth login
        run gh auth setup-git
    fi
    pacman_install tailscale
    as_root systemctl enable --now tailscaled
    if tailscale status >/dev/null 2>&1; then
        info "Tailscale: already connected"
    else
        as_root tailscale up     # prints a login URL; open it in the browser
    fi
    # Let this user control Tailscale without sudo (the bar widget needs it)
    as_root tailscale set --operator="$USER"
}

# Omarchy's native apps, built from source into Arch packages (no AUR entries yet):
#   Monologue  webcam recorder with a built-in trimmer   https://github.com/omacom/monologue
#   Hype       Markdown presentations, PDF/PPTX export    https://github.com/omacom/hype
# Both read the current Omarchy theme, so ~/.local/state/omarchy/current/theme points at the
# AERIS palette (dotfiles/home/.config/omarchy/themes/aeris, monochrome). Sources stay in
# ~/.local/src/<app>; aeris-update rebuilds one when upstream moves.
OMACOM_APPS=(monologue hype)

# omacom_app NAME: clone or fast-forward ~/.local/src/NAME, build, and install the package
omacom_app() {
    local name=$1 src="$HOME/.local/src/$1" repo="https://github.com/omacom/$1"
    if [[ -d $src/.git ]]; then
        run git -C "$src" pull -q --ff-only
    else
        run git clone -q "$repo" "$src"
    fi
    (( DRY )) && { info "[dry-run] build + install $name"; return 0; }
    (cd "$src" && ./bin/build >/dev/null && cd pkgbuild && makepkg -fsi --noconfirm) \
        || { warn "$name: build or install failed (see above); re-run: ./setup.sh omacom"; return 0; }
}

mod_omacom() {
    log "Omarchy apps: Monologue (camera recorder), Hype (presentations)"
    pacman_install base-devel git qt6-base qt6-declarative qt6-multimedia qt6-imageformats qt6-svg \
        ffmpeg libpulse source-highlight libwebp xdg-desktop-portal
    # The theme the apps follow: the AERIS palette, restored by the dotfiles module
    run mkdir -p "$HOME/.local/state/omarchy/current"
    if [[ -d $HOME/.config/omarchy/themes/aeris ]]; then
        run ln -sfn "$HOME/.config/omarchy/themes/aeris" "$HOME/.local/state/omarchy/current/theme"
    else
        warn "AERIS theme missing (run ./setup.sh dotfiles first); the apps fall back to their defaults"
    fi
    local app
    for app in "${OMACOM_APPS[@]}"; do omacom_app "$app"; done
    # Greyscale icons for the new apps, then a launcher restart so it indexes them with their icons
    [[ -x $HOME/.local/bin/make-mono-icons ]] && run "$HOME/.local/bin/make-mono-icons" >/dev/null
    if pgrep -x vicinae-server >/dev/null && (( ! DRY )); then (setsid vicinae server --replace >/dev/null 2>&1 &); fi
    info "Monologue: CMD+SHIFT+7 or the menu (Capture). Hype: SUPER+SHIFT+H or the launcher."
}

mod_aeris() {
    log "AERIS: watchlist timer, maps server, Ollama models, Claude Code + OpenCode"
    # The scripts (aeris-watch, aeris-inbox, aeris-onto), user units and the OpenCode/Claude
    # configs are restored by the dotfiles module; this wires them up.
    run systemctl --user daemon-reload
    if [[ -f $HOME/.config/systemd/user/aeris-watch.timer ]]; then
        run systemctl --user enable --now aeris-watch.timer      # hourly watchlist checks
    fi
    if [[ -f $HOME/.config/systemd/user/defence-maps.service && -f $HOME/maps/engine/serve.py ]]; then
        run systemctl --user enable --now defence-maps.service   # ~/maps on 127.0.0.1:8765
    fi

    # Local models: lock-screen telegram compression (aeris-status) and the AERIS board
    local model; model=$(llm_model)
    if gpu_has nvidia; then
        pacman_install ollama ollama-cuda
    else
        pacman_install ollama ollama-vulkan
        if [[ ! -f /etc/systemd/system/ollama.service.d/vulkan.conf ]]; then
            printf '[Service]\nEnvironment=OLLAMA_VULKAN=1\n' \
                | write_root_file /etc/systemd/system/ollama.service.d/vulkan.conf
            as_root systemctl daemon-reload
            as_root systemctl try-restart ollama.service
        fi
    fi
    as_root systemctl enable --now ollama.service
    # A just-started server takes a few seconds to accept requests
    if have ollama && (( ! DRY )); then
        for _ in {1..20}; do ollama list >/dev/null 2>&1 && break; sleep 1; done
    fi
    if have ollama && ! ollama list 2>/dev/null | grep -q "^$model"; then
        run ollama pull "$model" || warn "Model pull failed; aeris-status uses OpenRouter or raw headlines"
    fi
    if ! gpu_has nvidia; then
        # The OpenCode agents' local models don't fit in 4 GB: all on OpenRouter
        # (aeris-status/aeris-watch use OpenRouter by themselves whenever Ollama is down)
        if [[ -f $HOME/.config/opencode/opencode.json ]]; then
            run sed -i -E 's#"ollama/[^"]*"#"openrouter/z-ai/glm-5.3-flash"#' "$HOME/.config/opencode/opencode.json"
            run sed -i -E 's#^model: ollama/.*#model: openrouter/z-ai/glm-5.3-flash#' "$HOME"/.config/opencode/agents/*.md
        fi
        grep -qsE '^(export )?OPENROUTER(_API)?_KEY=' "$HOME/.env" || grep -qs openrouter "$HOME/.local/share/opencode/auth.json" \
            || info "OpenRouter key (fallback when Ollama is down): OPENROUTER_KEY=... in ~/.env (chmod 600) or 'opencode auth login'"
    fi

    # Claude Code (native installer); OpenCode is the AERIS fork, installed by hand
    have claude || run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    # Claude Code's TTS hooks (Stop / Notification -> aeris-agent-notify) are already in
    # ~/.claude/settings.json, restored by the dotfiles module; the voice itself is the tts module
    if ! have opencode && [[ ! -x $HOME/.opencode/bin/opencode ]]; then
        warn "OpenCode (AERIS fork) not installed; its config is already in ~/.config/opencode"
    fi
    info "~/maps (defence maps app + data) lives in its own repo: ./setup.sh maps installs it"
}

# Spoken announcements: Kokoro (bf_emma) behind aeris-speak, and the aeris-announce
# user service that speaks watchlist/pass/alert events. The scripts and the unit arrive
# with dotfiles; this installs the voice they need
mod_tts() {
    log "TTS voice: Kokoro venv, model files, aeris-announce service"
    local base="$HOME/.local/share/aeris"
    local venv="$base/tts-venv" models="$base/tts-models"
    local url=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
    local f

    pacman_install python pipewire libnotify dunst

    if [[ ! -x $venv/bin/python3 ]]; then
        run mkdir -p "$base"
        run python3 -m venv "$venv"
    fi
    if (( DRY )) || ! "$venv/bin/python3" -c 'import kokoro_onnx, soundfile' >/dev/null 2>&1; then
        run "$venv/bin/pip" install --quiet kokoro-onnx soundfile || warn "pip install failed; re-run: ./setup.sh tts"
    fi

    run mkdir -p "$models"
    for f in kokoro-v1.0.onnx voices-v1.0.bin; do
        [[ -s $models/$f ]] && continue
        run curl -fL --retry 3 -o "$models/$f.part" "$url/$f" \
            && run mv "$models/$f.part" "$models/$f" \
            || warn "Download of $f failed; re-run: ./setup.sh tts"
    done

    # Point aeris-speak at the canonical install locations (older copies used ~/tts-samples)
    if [[ -f $HOME/.local/bin/aeris-speak ]]; then
        run sed -i -E \
            -e 's|^VENV=.*|VENV="$HOME/.local/share/aeris/tts-venv"|' \
            -e 's|^MODEL=.*|MODEL="$HOME/.local/share/aeris/tts-models/kokoro-v1.0.onnx"|' \
            -e 's|^VOICES=.*|VOICES="$HOME/.local/share/aeris/tts-models/voices-v1.0.bin"|' \
            "$HOME/.local/bin/aeris-speak"
    else
        warn "aeris-speak not found; run the 'dotfiles' module first"
    fi

    run systemctl --user daemon-reload
    if [[ -f $HOME/.config/systemd/user/aeris-announce.service ]]; then
        run systemctl --user enable --now aeris-announce.service
    fi
    info "Test: aeris-speak \"AERIS voice online\""
}

mod_theme() {
    log "Monochrome theme: neon gradient focus border, black inactive border, greyscale icons, one text size"

    # Window borders: rotating white/green/purple gradient active (2 px), black inactive
    local hypr="$HOME/.config/hypr/hyprland.lua"
    if [[ -f $hypr ]]; then
        run sed -i -E \
            -e 's|^(\s*active_border\s*=\s*).*|\1{ colors = { "rgba(f2f2ffff)", "rgba(39ff88ff)", "rgba(b44dffff)" }, angle = 45 },   -- cyberpunk: white, green, purple|' \
            -e 's|^(\s*inactive_border\s*=\s*).*|\1"rgba(000000ff)",   -- AerisOS: black|' \
            "$hypr"
    fi

    # Greyscale icon theme "Mono" (built by ~/.local/bin/make-mono-icons)
    pacman_install breeze-icons
    if [[ -x $HOME/.local/bin/make-mono-icons ]]; then
        run "$HOME/.local/bin/make-mono-icons"
    else
        warn "make-mono-icons not found; run the 'dotfiles' module first"
    fi
    run gsettings set org.gnome.desktop.interface icon-theme Mono

    # Cursor: Bibata Modern Classic (also set as XCURSOR_THEME/HYPRCURSOR_THEME in hyprland.lua);
    # ~/.icons/default makes it the fallback for apps that read neither
    aur_install bibata-cursor-theme-bin
    run gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Classic
    run gsettings set org.gnome.desktop.interface cursor-size 24
    gtk_ini_set "$HOME/.config/gtk-3.0/settings.ini" gtk-cursor-theme-name Bibata-Modern-Classic
    gtk_ini_set "$HOME/.config/gtk-4.0/settings.ini" gtk-cursor-theme-name Bibata-Modern-Classic
    if (( ! DRY )); then
        mkdir -p "$HOME/.icons/default"
        printf '[Icon Theme]\nInherits=Bibata-Modern-Classic\n' > "$HOME/.icons/default/index.theme"
    fi
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gtk_ini_set "$HOME/.config/gtk-3.0/settings.ini" gtk-icon-theme-name Mono
    gtk_ini_set "$HOME/.config/gtk-4.0/settings.ini" gtk-icon-theme-name Mono

    # One text size everywhere: 9 pt (= 12 px in the Quickshell bar/dock QML, ghostty font-size 9)
    run gsettings set org.gnome.desktop.interface font-name 'Söhne 9'
    run gsettings set org.gnome.desktop.interface document-font-name 'Söhne 9'
    run gsettings set org.gnome.desktop.interface monospace-font-name 'Söhne Mono 9'
    gtk_ini_set "$HOME/.config/gtk-3.0/settings.ini" gtk-font-name 'Söhne 9'
    gtk_ini_set "$HOME/.config/gtk-4.0/settings.ini" gtk-font-name 'Söhne 9'

    # Apply live if we're inside Hyprland
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        run hyprctl reload >/dev/null
        # ghostty picks up its config on the next new window; no reload signal needed
        run pkill -f "^qs -p.*aeris-dock" || true     # dock-autohide relaunches it with the new icon theme
    fi
}

mod_safety() {
    log "Safety: btrfs snapshots around package installs, firewall, firmware check"
    pacman_install snapper snap-pac ufw fwupd

    # Snapper: pre/post snapshots of / for every pacman transaction (snap-pac), no hourly ones
    if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
        if [[ ! -f /etc/snapper/configs/root ]]; then
            as_root snapper -c root create-config /
            as_root snapper -c root create --description "Baseline after AerisOS setup"
        fi
        as_root snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
        as_root systemctl enable --now snapper-cleanup.timer
    else
        warn "Root isn't btrfs; skipping snapshots"
    fi

    # Firewall: block incoming, allow outgoing, allow LocalSend
    as_root ufw default deny incoming
    as_root ufw default allow outgoing
    as_root ufw allow 53317 comment 'LocalSend'
    as_root ufw --force enable
    as_root systemctl enable ufw.service

    # Firmware: only report available BIOS/SSD updates, never install
    run fwupdmgr refresh --force || true
    run fwupdmgr get-updates 2>/dev/null || true
}

mod_boot() {
    log "Boot branding: menu name \"$OS_NAME\", full-screen splash, animated Plymouth boot"
    local preset=/etc/mkinitcpio.d/linux.preset
    local osrel=/etc/kernel/boot-os-release
    local splash=/etc/kernel/splash.bmp
    [[ -f $preset ]] || { warn "$preset not found (needs mkinitcpio + UKI); skipping"; return 0; }

    # Still splash + Plymouth layers, rendered at the screen's native size
    local tmp; tmp=$(mktemp -d)
    build_brand "$tmp"
    as_root install -m644 "$tmp/splash.bmp" "$splash"

    # Plymouth: the splash with a light gliding along its hairline, until the login screen
    pacman_install plymouth
    local theme=/usr/share/plymouth/themes/aeris
    as_root install -Dm644 -t "$theme" "$AERIS/plymouth/aeris/aeris.plymouth" "$AERIS/plymouth/aeris/aeris.script" \
        "$tmp/bg.png" "$tmp/sweep.png"
    rm -rf "$tmp"
    printf '[Daemon]\nTheme=aeris\nShowDelay=0\nDeviceScale=1\n' | write_root_file /etc/plymouth/plymouthd.conf
    if ! grep -qE '^HOOKS=.*[ (]plymouth[ )]' /etc/mkinitcpio.conf; then
        as_root sed -i -E '/^HOOKS=/ s/([ (])udev([ )])/\1udev plymouth\2/' /etc/mkinitcpio.conf
    fi

    # Boot menu name, without touching the real /etc/os-release
    sed -e "s|^NAME=.*|NAME=\"$OS_NAME\"|" -e "s|^PRETTY_NAME=.*|PRETTY_NAME=\"$OS_NAME\"|" \
        /usr/lib/os-release | write_root_file "$osrel"

    # Native resolution in the boot loader: firmware defaults to 800x600 here, and
    # systemd-stub skips any splash larger than the screen
    local loader=/boot/loader/loader.conf
    if (( DRY )); then info "[dry-run] set console-mode max in $loader"
    elif ! sudo grep -q '^console-mode max' "$loader" 2>/dev/null; then
        sudo cp -n "$loader" "$loader.bak" 2>/dev/null || true
        if sudo grep -qE '^#?console-mode' "$loader" 2>/dev/null; then
            sudo sed -i -E 's/^#?console-mode.*/console-mode max/' "$loader"
        else
            echo 'console-mode max' | sudo tee -a "$loader" >/dev/null
        fi
    fi
    # No boot menu: straight from the firmware logo to the splash (hold Space at power-on to show it)
    if (( DRY )); then info "[dry-run] set timeout 0 in $loader"
    elif ! sudo grep -q '^timeout 0$' "$loader" 2>/dev/null; then
        if sudo grep -q '^timeout' "$loader" 2>/dev/null; then
            sudo sed -i 's/^timeout.*/timeout 0/' "$loader"
        else
            echo 'timeout 0' | sudo tee -a "$loader" >/dev/null
        fi
    fi

    # Quiet boot: without it the kernel prints over the splash the instant it's drawn
    local cmdline=/etc/kernel/cmdline arg
    if [[ -f $cmdline ]]; then
        [[ -f $cmdline.bak ]] || as_root cp "$cmdline" "$cmdline.bak"
        for arg in quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0; do
            grep -qw -- "$arg" "$cmdline" || as_root sed -i "s|\$| $arg|" "$cmdline"
        done
    else
        warn "$cmdline not found; add 'quiet loglevel=3' to your kernel command line so the splash stays visible"
    fi

    [[ -f $preset.bak ]] || as_root cp "$preset" "$preset.bak"
    as_root sed -i "s|^#\?default_options=.*|default_options=\"--osrelease $osrel --splash $splash\"|" "$preset"
    as_root mkinitcpio -p linux

    # T2 Macs boot linux-t2 from a plain loader entry (no UKI, no /etc/kernel/cmdline):
    # quiet options on that entry, Plymouth in its initramfs
    if is_t2; then
        local entry
        for entry in $(sudo grep -l 'vmlinuz-linux-t2' /boot/loader/entries/*.conf 2>/dev/null); do
            for arg in quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0; do
                sudo grep -qE "^options.* $arg( |$)" "$entry" || as_root sed -i "/^options/ s|\$| $arg|" "$entry"
            done
        done
        as_root mkinitcpio -p linux-t2
    fi
    info "Reboot to see it. OS_NAME stays ASCII because firmware boot menus often can't draw Æ (the splash still shows ÆRIS)."
}

# Razer laptops: razer-control-revived (battery health optimizer, power modes, fans,
# logo) built from source, plus a timer that holds the battery between 90 and 95%
mod_razer() {
    log "Razer: razer-control-revived + battery held at 90-95%"
    local src="$HOME/.local/src/razer-control-revived"
    local repo=https://github.com/encomjp/razer-control-revived
    if ! lsusb 2>/dev/null | grep -qi '1532:.*Razer'; then
        warn "No Razer laptop controller found; skipping"
        return 0
    fi
    pacman_install rust dbus libusb hidapi pkgconf gtk4 libadwaita git

    if [[ -d $src/.git ]]; then
        run git -C "$src" pull --ff-only
    else
        run git clone "$repo" "$src"
    fi
    (( DRY )) || (cd "$src/razer_control_gui" && cargo build --release)

    local b="$src/razer_control_gui"
    as_root mkdir -p /usr/share/razercontrol
    as_root install -m755 "$b/target/release/razer-cli" /usr/bin/razer-cli
    as_root install -m755 "$b/target/release/daemon" /usr/bin/razer-daemon
    as_root install -m755 "$b/target/release/razer-settings" /usr/bin/razer-settings
    as_root install -m644 "$b/data/devices/laptops.json" /usr/share/razercontrol/laptops.json
    as_root install -m644 "$b/data/gui/com.encomjp.razer-settings.desktop" /usr/share/applications/
    as_root install -Dm644 "$b/data/gui/com.github.encomjp.razercontrol.svg" \
        /usr/share/icons/hicolor/scalable/apps/com.github.encomjp.razercontrol.svg
    as_root install -m644 "$b/data/services/systemd/razercontrol.service" /usr/lib/systemd/user/razercontrol.service
    # Access for the logged-in user only (upstream uses world-writable 0666); 70- so uaccess
    # is set before 73-seat-late.rules applies it
    sed 's/, MODE="0666"//' "$b/data/udev/99-hidraw-permissions.rules" | write_root_file /etc/udev/rules.d/70-razer-hidraw.rules
    as_root rm -f /etc/udev/rules.d/99-hidraw-permissions.rules
    as_root udevadm control --reload-rules
    as_root udevadm trigger --action=change --subsystem-match=hidraw

    # Battery: Razer's optimizer only goes to 80%, so a timer pauses charging at 95%
    run mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
    run install -m755 "$AERIS/bin/aeris-charge-limit" "$HOME/.local/bin/aeris-charge-limit"
    run install -m644 "$AERIS/battery/aeris-charge-limit.service" "$AERIS/battery/aeris-charge-limit.timer" \
        "$HOME/.config/systemd/user/"
    run systemctl --user daemon-reload
    run systemctl --user enable --now razercontrol.service aeris-charge-limit.timer
    info "GUI: Razer Settings in the app launcher. CLI: razer-cli read bho / write bho off"
}

# First-run wizard: the personal answers (git identity, hostname, maps app),
# saved to ~/.config/aerisos/setup.conf and reused by every later run.
# In a full run it only asks once; change answers with: ./setup.sh wizard
mod_wizard() {
    if [[ -f $CONF && $WIZARD_FORCED -eq 0 ]]; then
        info "Using saved answers from $CONF (change them: ./setup.sh wizard)"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        warn "No terminal attached: skipping the wizard (run './setup.sh wizard' later)"
        return 0
    fi
    log "Wizard: a few personal answers, saved to $CONF"

    local def_name def_email name email host cur_host maps maps_repo seckey
    def_name=${AERIS_GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}
    def_email=${AERIS_GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}
    cur_host=$(hostnamectl hostname 2>/dev/null || hostname)
    read -rp "  Your name (for git commits) [${def_name:-skip}]: " name; name=${name:-$def_name}
    read -rp "  Your email (for git commits) [${def_email:-skip}]: " email; email=${email:-$def_email}
    read -rp "  Hostname for this machine [$cur_host]: " host; host=${host:-$cur_host}
    read -rp "  Install the defence-maps app? Needs access to its private repo [y/N]: " maps
    if [[ ${maps,,} == y* ]]; then
        maps=yes
        read -rp "  Maps repo URL [${AERIS_MAPS_REPO:-https://github.com/hjbarraza/defence-maps.git}]: " maps_repo
        maps_repo=${maps_repo:-${AERIS_MAPS_REPO:-https://github.com/hjbarraza/defence-maps.git}}
    else
        maps=no; maps_repo=${AERIS_MAPS_REPO:-}
    fi
    read -rp "  Guard login with a security key (Titan, YubiKey, any FIDO2 key)? [y/N]: " seckey
    [[ ${seckey,,} == y* ]] && seckey=yes || seckey=no

    if (( ! DRY )); then
        mkdir -p "$(dirname "$CONF")"
        cat > "$CONF" <<EOF
# AerisOS wizard answers (shell vars, sourced by setup.sh).
# Edit by hand or re-run: ./setup.sh wizard
AERIS_GIT_NAME="$name"
AERIS_GIT_EMAIL="$email"
AERIS_MAPS="$maps"
AERIS_MAPS_REPO="$maps_repo"
AERIS_SECURITY_KEY="$seckey"
EOF
        chmod 600 "$CONF"
        # shellcheck disable=SC1090
        source "$CONF"
    fi
    [[ $host == "$cur_host" ]] || as_root hostnamectl set-hostname "$host"
    info "Saved. Hardware extras when they apply: ./setup.sh razer | gamesdrive"
}

# The defence-maps app (~/maps): lives in its own private repo, so installing it
# is optional. Selected in the wizard, or run directly: ./setup.sh maps
mod_maps() {
    if [[ ${AERIS_MAPS:-no} != yes && $MAPS_FORCED -eq 0 ]]; then
        info "Maps app not selected in the wizard; install anytime: ./setup.sh maps"
        return 0
    fi
    log "Defence maps: clone/update ~/maps from its own repo"
    pacman_install git
    if [[ -d $HOME/maps/.git ]]; then
        run git -C "$HOME/maps" pull --ff-only || warn "Pull failed; ~/maps left as it is"
    elif [[ -e $HOME/maps ]]; then
        warn "~/maps exists but is not a git clone; leaving it alone"
    else
        if [[ -z ${AERIS_MAPS_REPO:-} ]]; then
            [[ -t 0 ]] || { warn "AERIS_MAPS_REPO not set; skipping"; return 0; }
            read -rp "  Maps repo URL: " AERIS_MAPS_REPO
            [[ -n $AERIS_MAPS_REPO ]] || { warn "No URL given; skipping"; return 0; }
        fi
        run git clone "$AERIS_MAPS_REPO" "$HOME/maps" || { warn "Clone failed (no access to the private repo?)"; return 0; }
    fi
    # The user unit arrives with dotfiles; serve ~/maps at 127.0.0.1:8765
    if [[ -f $HOME/.config/systemd/user/defence-maps.service && -f $HOME/maps/engine/serve.py ]]; then
        run systemctl --user enable --now defence-maps.service
    fi
}

# Security key (Titan, YubiKey, any FIDO2/U2F): password + key 2FA on hyprlock
# and SDDM, logout + SDDM restart when the key is unplugged. tty login stays
# password-only (recovery). OPTIONAL: runs only if chosen in the wizard or
# named (./setup.sh titan). The script auto-detects whatever key is plugged in;
# enrollment needs a touch and is skipped if a key is already enrolled.
mod_titan() {
    if [[ ${AERIS_SECURITY_KEY:-no} != yes && $TITAN_FORCED -eq 0 ]]; then
        info "Security key not selected in the wizard; set up anytime: ./setup.sh titan"
        return 0
    fi
    log "Security key: U2F second factor for lock/login + logout on unplug"
    if [[ ! -t 0 ]]; then
        warn "No terminal attached (enrollment needs a key touch); run later: ./setup.sh titan"
        return 0
    fi
    as_root bash "$AERIS/titan/setup-titan-pam.sh"
}

# Not part of "all": copy this machine's setup back into the repo
mod_snapshot() {
    log "Snapshot: saving configs and package lists into $AERIS"

    local present=() rel
    for rel in "${HOME_PATHS[@]}"; do [[ -e $HOME/$rel ]] && present+=("$rel"); done
    if (( DRY )); then info "[dry-run] copy ${#present[@]} paths into $DOT/home"
    else
        rm -rf "$DOT/home"
        mkdir -p "$DOT/home"
        tar -C "$HOME" "${EXCLUDES[@]}" -cf - "${present[@]}" | tar -C "$DOT/home" -xf -
    fi

    present=()
    for rel in "${SYSTEM_PATHS[@]}"; do [[ -e $rel ]] && present+=("${rel#/}"); done
    if (( ${#present[@]} && ! DRY )); then
        rm -rf "$DOT/system"
        mkdir -p "$DOT/system"
        tar -C / "${EXCLUDES[@]}" -cf - "${present[@]}" | tar -C "$DOT/system" -xf -
    fi

    if (( DRY )); then info "[dry-run] write package lists"; return; fi
    mkdir -p "$PKG"
    # wl-clipboard (aeris-ask) is often only a dependency here, so -Qqe would drop it
    { pacman -Qqen; echo wl-clipboard; } | sort -u > "$PKG/pacman.txt"
    pacman -Qqem > "$PKG/aur.txt"
    info "$(wc -l < "$PKG/pacman.txt") repo packages, $(wc -l < "$PKG/aur.txt") AUR packages"
    "$AERIS/archinstall/make-config" >/dev/null   # archinstall config follows the package list
    info "Configs: $(find "$DOT" -type f | wc -l) files"
}

# --- main ----------------------------------------------------------------------

usage() { sed -n '2,20p' "$0" | sed 's/^# \?//'; }

selected=()
for arg in "$@"; do
    case $arg in
        --dry-run|-n) DRY=1 ;;
        --list)       printf '%s\n' "${MODULES[@]}"; printf '%s (optional)\n' "${OPTIONAL[@]}"; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        all)          selected+=("${MODULES[@]}") ;;
        *)
            declare -F "mod_$arg" >/dev/null || { echo "Unknown module: $arg (see --list)" >&2; exit 1; }
            [[ $arg == wizard ]] && WIZARD_FORCED=1
            [[ $arg == maps ]] && MAPS_FORCED=1
            [[ $arg == titan ]] && TITAN_FORCED=1
            selected+=("$arg") ;;
    esac
done
(( ${#selected[@]} )) || selected=("${MODULES[@]}")

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root." >&2; exit 1; }

# Everything shown is also kept, so a failed run can be read afterwards
if (( ! DRY )); then
    LOG="$HOME/.local/state/aerisos/setup-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "${LOG%/*}"
    exec > >(tee -a "$LOG") 2>&1
    info "Log: $LOG"
fi
if (( ! DRY )) && printf '%s\n' "${selected[@]}" | grep -vx snapshot >/dev/null; then
    if [[ -t 0 ]]; then
        sudo -v
        # Keep sudo alive for long installs
        while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done &
        # The pid now: $! at exit is whatever ran in the background last, and a failed kill
        # there tripped the ERR trap, blaming the last module after a clean run
        trap "kill $! 2>/dev/null || true" EXIT
    else
        warn "No terminal attached: steps that need sudo will fail (run this in a terminal)"
    fi
fi

current=""
trap 'warn "Failed in module \"$current\" (line $LINENO). Fix it and re-run: ./setup.sh $current (log: ${LOG:-none})"' ERR
for current in "${selected[@]}"; do
    "mod_$current"
done
log "$OS_NAME: done (${selected[*]})"

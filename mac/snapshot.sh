#!/bin/bash
# Capture the MacBook Air's desktop settings into mac/mba/ (the macOS counterpart of
# ./setup.sh snapshot): yabai, skhd, sketchybar, karabiner, terminals, shells, own scripts,
# the LaunchAgents that start the tiling stack, and a Brewfile. Logins stay out: no gh,
# gcloud, rclone, Raycast, opencode or app data, no ~/.ssh, no env files.
#
#   mac/snapshot.sh [HOST]      default: mba

set -euo pipefail

host=${1:-mba}
dest="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/mba"
paths=(
  .config/yabai .config/skhd .config/sketchybar .config/karabiner
  .config/ghostty .config/btop .config/cava .config/mpv .config/fish/config.fish
  .zshrc .zprofile .gitconfig
  .local/bin/aeris
  Library/LaunchAgents/com.asmvik.yabai.plist Library/LaunchAgents/com.koekeishiya.skhd.plist
  Library/LaunchAgents/sh.brew.sketchybar.plist
)

rm -rf "$dest"
mkdir -p "$dest/home"
for p in "${paths[@]}"; do
  if ssh "$host" "test -e \"\$HOME/$p\""; then
    mkdir -p "$dest/home/$(dirname "$p")"
    scp -rq "$host:$p" "$dest/home/$p"
  fi
done
# Editor and tool leftovers, as in setup.sh
rm -rf "$dest/home/.config/karabiner/automatic_backups"
find "$dest" \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak[0-9]*' -o -name '.DS_Store' \) -delete
# Shell files hold API keys on the Mac: keep the line, blank the value
for f in "$dest/home/.zshrc" "$dest/home/.zprofile" "$dest/home/.config/fish/config.fish"; do
  if [[ -f $f ]]; then
    sed -E -i.tmp 's/^([[:space:]]*(export|set -gx)[[:space:]]+[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASS)[A-Za-z0-9_]*[ =]).*/\1"<redacted>"/' "$f"
    rm -f "$f.tmp"
  fi
done
ssh "$host" 'PATH=/opt/homebrew/bin:$PATH brew bundle dump --file=- --force' > "$dest/Brewfile"
echo "captured $(find "$dest" -type f | wc -l | tr -d ' ') files from $host into $dest"

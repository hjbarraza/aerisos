# mac

The MacBook Air (`mba`: macOS, yabai + skhd + sketchybar), kept in step with rzr by hand.

| Path | Job |
|---|---|
| `grid` | Installed to `~/.local/bin/grid`. `grid` tiles the current yabai space on rzr's Swiss grid (12 columns: 1 full, 2 halves, 3+ as 3 \| 6 \| 3 with even stacks), `grid off` goes back to bsp. Gridded spaces re-tile as windows come and go, through the yabai signals at the end of `yabairc`. |
| `snapshot.sh` | Captures the Mac's desktop settings into `mba/` over ssh: `mac/snapshot.sh [host]`. Run it after changing anything there, then commit. |
| `mba/home/` | yabai, skhd, sketchybar, karabiner, ghostty (AERIS theme), btop, cava, mpv, zsh, git, the `aeris` script, and the LaunchAgents that start yabai, skhd and sketchybar. API keys in the shell files are replaced with `"<redacted>"`; logins (gh, gcloud, rclone, Raycast, opencode, ssh) are never captured. |
| `mba/Brewfile` | Every Homebrew tap, formula, cask and Mac App Store app: `brew bundle --file=mac/mba/Brewfile` on a fresh Mac. |

Restore on a Mac: `brew bundle --file=mba/Brewfile`, copy `mba/home/` into `~` (put the real keys back into `~/.zshrc`), copy `grid` to `~/.local/bin/`, then `yabai --start-service`, `skhd --start-service` and `brew services start sketchybar`.

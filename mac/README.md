# mac

The MacBook Air (`mba`, macOS, yabai + skhd + sketchybar), kept in step with rzr by hand.

| File | Installed to | Job |
|---|---|---|
| `grid` | `~/.local/bin/grid` | `grid` tiles the current yabai space on rzr's Swiss grid (12 columns: 1 full, 2 halves, 3+ as 3 \| 6 \| 3 with even stacks), `grid off` goes back to bsp. Spaces stay gridded as windows come and go through the yabai signals at the end of `yabairc`. |
| `mba/yabairc` | `~/.config/yabai/yabairc` | Tiling: bsp, 8 px padding and gutters, the 26 px sketchybar, the grid signals |
| `mba/skhdrc` | `~/.config/skhd/skhdrc` | Hotkeys ported from rzr's hyprland.lua |

Install: `scp mac/grid mba:.local/bin/grid`; the configs likewise, then `yabai --restart-service` and `skhd --restart-service`.

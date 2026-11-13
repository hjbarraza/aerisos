# AerisOS on macOS

The Hyprland desktop, ported to a Mac: tiling, hotkeys, bar and mouse habits.
`home/` mirrors `$HOME`, like `dotfiles/home/` does for Linux.

| File | Job |
|---|---|
| `home/.config/yabai/yabairc` | Tiling (bsp, 8px grid), focus follows mouse, new windows open on the screen under the mouse. |
| `home/.config/skhd/skhdrc` | Hotkeys. Each `# comment` names the group shown in the cheat sheet. |
| `home/.config/sketchybar/sketchybarrc` | Top bar. |
| `home/.local/bin/grid`, `tile`, `floating` | Layout of the current space: Swiss grid (3 \| 6 \| 3 columns), yabai tiling, or plain macOS. `floating` opens Magnet; `tile` and `grid` quit it. The bar's layout label cycles the same three. |
| `home/.hammerspoon/init.lua` | Select to copy, right-click in a text field to paste (Option + right-click for the menu). |
| `keysheet/` | ⌘K cheat sheet: a searchable list of the skhd hotkeys. |

## Install

```bash
brew install koekeishiya/formulae/yabai koekeishiya/formulae/skhd FelixKratz/formulae/sketchybar jq
brew install --cask hammerspoon
cp -R mac/home/. ~/
mac/keysheet/build.sh
yabai --start-service && skhd --start-service && brew services start sketchybar
open -a Hammerspoon
```

Then grant Accessibility to yabai, skhd and Hammerspoon in System Settings → Privacy & Security.

## Notes

- yabai runs with SIP on: tiling works; switching spaces from a hotkey does not.
- yabai cannot move windows onto a screen showing a macOS full-screen app. Use ⌃⌥↩ (maximize) instead of the green button to keep windows in the tiling layout.

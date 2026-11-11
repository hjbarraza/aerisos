# AerisOS, Chromebook edition

The AerisOS monochrome look on a low-end Chromebook: Hyprland, the same keys,
the same palette and Söhne type, with lighter programs. Built for a Samsung
Chromebook 4 (board `BLUEBIRD`, reports itself as `Casta`; Celeron N4020, 4 GB RAM).

It is a separate, small profile. The main `setup.sh` targets a laptop with a
discrete GPU and is too heavy for this hardware.

## Install

1. Put Linux on the Chromebook: developer mode, MrChromebox `RW_LEGACY` firmware,
   then EndeavourOS (Xfce) installed to a USB drive or SD card. ChromeOS stays on
   the internal disk. Boot each time with `Ctrl+L`, `Esc`, Boot Manager.
2. Copy this folder to `~/aerisos/chromebook` and your licensed fonts to
   `~/.local/share/fonts`: Söhne in `soehne/`, Die Grotesk in `die-grotesk/`. The bar icons need `SymbolsNerdFont-Regular.ttf`
   in `~/.local/share/fonts`.
3. Run `~/aerisos/chromebook/setup.sh` as your normal user. It is safe to re-run.
4. Log out, pick **Hyprland** at the login screen, log in.

## What differs from AerisOS

| AerisOS | Chromebook edition | Why |
|---|---|---|
| Ghostty | kitty | lighter |
| Brave, web apps in app windows | Firefox, new windows | one browser only |
| Quickshell bar and dock | Waybar, same glyphs, no dock | far less RAM |
| Vicinae, hyprlauncher | wofi | lighter |
| Blur, shadows, animations | off | small GPU |
| swayosd | plain volume and brightness keys | fewer services |
| Lock and login screens with live feeds | plain lock screen, stock login screen | no status service |
| Print-key screenshots | `Super+Shift+A`, `Super+Alt+A`, `Super+Shift+E` | no Print key |
| 30-minute suspend | none | suspend is untested here |
| Söhne 9 pt everywhere | Die Grotesk 10 pt for the interface, Söhne Mono for code, Söhne for the marks | owner's choice; 1366×768 panel at scale 1 |

Left out for RAM: Obsidian, Signal, Sublime Text, Steam, Ollama, Voxtype
(no AVX, two slow cores), the AERIS intelligence layer.

## Hardware notes

- **Microphone.** The internal mic device has four channels and only the first
  two are live. `pipewire.conf.d/10-internal-mic.conf` adds a virtual source
  with those two; make it the default once with `wpctl set-default <id>`.
- **Memory.** Compressed swap in RAM (zram, the size of RAM) is used first; a
  4 GB swap file is the slow safety net under it.
- **USB-C crash.** Kernel 7.2.15 crashed once in `cros_usbpd_notify` when a
  USB-C device was plugged in; programs that read the battery then hang until a
  reboot. `blacklist cros_usbpd_notify` does not stop it loading (another driver
  pulls it in).
- **Bar restarts.** Restart Waybar with `pkill -x waybar; waybar &` only on a
  healthy system; after the crash above, killed bars stay on screen.

## Files

- `setup.sh` — packages, dotfiles, memory, key-only SSH, plain black login screen with a centred form, boot splash, Tailscale.
- `packages.txt` — what is installed on top of EndeavourOS.
- `home/` — copied into your home folder as is.
- `splash.svg` — the boot splash: raven, `tinyraven`, "ONTOLOGY TERMINAL", ÆRIS OS · 小鴉.
- `home/.config/tinyraven/phrases.txt` — the lines shown under "ONTOLOGY TERMINAL", one picked at random each boot and in the terminal greeting. Edit it and run `setup.sh` again.
- `plymouth/` — the boot theme that shows it, with a light on the hairline.
- `firefox/user.js` — Firefox memory settings for 4 GB, copied into each profile by `setup.sh`.
- `boot/` — the hook that names the boot menu entries "AerisOS TinyRaven". The menu is hidden; hold `Space` at boot to show it.
- `move-to-internal-disk.sh` — moves the running system from the SD card to the internal disk (erases ChromeOS). Read its header first.
- `firmware/` — replaces the firmware's hare logo with the raven. Prepared, not yet built or flashed; read its README first.

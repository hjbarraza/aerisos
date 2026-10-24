# The shell (Quickshell)

One Quickshell process, `~/.config/quickshell/aeris/shell.qml`, draws the top bar and the pill
dock. Hyprland starts it at login (`hyprland.lua`, the autostart block). The source of truth is
`dotfiles/home/.config/quickshell/aeris/` in this repo; `./setup.sh dotfiles` installs it and
`./setup.sh snapshot` captures it back. Quickshell 0.3.2.

## Where things go

```
aeris/
  shell.qml          ShellRoot: the IPC handlers and one line each for Bar and Dock. Nothing else.
  Commons/           Singletons, imported as `import qs.Commons`
    Theme.qml        colors, fonts, sizes; user overrides from ~/.config/aeris/shell.json
    Status.qml       /var/lib/aeris/status.json, parsed on change, plus what the bar derives from it
    Shell.qml        barShown, refreshTick, sh(cmd), isoWeek(date)
    qmldir           registers the three singletons
  Ui/                Shared components, `import qs.Ui`
    StatusModule.qml a Waybar-style module: runs a command, shows its JSON
    Glyph.qml        a Nerd Font icon with the bar's padding
    Caption.qml      small spaced capitals (pills, popup headings)
    qmldir
  Bar/
    Bar.qml          the PanelWindow and the three groups; order here is order on screen
    <Widget>.qml     one file per widget: Mark, Workspaces, Toggles, Clock, Voxtype, Alerts,
                     Tailscale, TailscalePopup, Network, Volume, Battery, Drawer
  Dock/
    Dock.qml         the pill and its hover autohide
```

Rules that follow from this layout:

- **A new widget is a new file in `Bar/`** and one line in `Bar/Bar.qml`. It never goes inline.
  Widgets in the same directory see each other by filename without an import.
- **Singletons are imported through `qs.Commons`, never by relative path.** A relative import
  gives the file its own private copy of the singleton, so `Status` would be empty there.
- **No literal colors, font names or sizes in widgets.** They come from `Theme`. A new token is a
  key in `Theme.defaults` plus a readonly property, and is then overridable from `shell.json`.
- **`shell.qml` stays tiny.** State lives in `Commons/Shell.qml`; UI lives in `Bar/` and `Dock/`.
- **A second `qs -p` is not how a popup is added.** It is a `PopupWindow` or `PanelWindow` in a
  file under `Bar/` or `Dock/`, inside this process. (`aeris-orbit` still launches one, inherited
  from before this layout; folding it in is the open task.)

## The three groups of the bar

`Bar/Bar.qml` anchors three groups inside the PanelWindow: the left group hangs off the left
edge, the right group off the right edge, and `Clock` sits on the exact horizontal center of the
screen with `Toggles` anchored to its left edge and `Voxtype` and `Alerts` to its right. The
clock therefore never moves when a side group grows (the drawer opening, a long alert). Put a
new widget in whichever group it belongs to; a center widget goes on the side of the clock
that should absorb its width.

## Getting data in

In order of preference, the first that fits:

1. **A Quickshell service that signals.** `UPower` (Battery), `Pipewire` (Volume), `Hyprland`
   (Workspaces), `SystemTray`, `ToplevelManager` (Dock). Bind to its properties; nothing to poll.
2. **A file the collector writes.** `Status` already watches `status.json` with
   `FileView { watchChanges: true }`. Add a derived readonly property to `Status`, not a second
   FileView, and bind to it from the widget (see `Alerts.qml`).
3. **A long-lived process that streams events.** `Network.qml` runs `nmcli monitor` through a
   `SplitParser` and re-queries on each line; `Voxtype.qml` streams `voxtype status --follow`.
   One process for the life of the shell, no timer.
4. **A push from the command that changed the state.** Toggle commands end with
   `aeris-shell -q bar refresh`; every `StatusModule` re-runs on that. If you add a command that
   changes something the bar shows, push from the command rather than shortening a timer.
5. **A timer, last.** Only for state with no change signal. 60 s or longer, and gated with
   `active: drawer.open` (or the panel's visibility) when nobody sees the result while closed.
   `Drawer.qml` does this for bluetooth, backlight and power profile. Write the reason next to it.

A `StatusModule` is the quick way to show a command's output: give it `cmd` (Waybar JSON out,
`{"text","class","tooltip"}`, exit 0, empty text hides it), optionally `interval`, `active`,
`onClick`, `onRightClick`. `class: "off"` or `"disconnected"` renders dim.

## Talking to the shell

`aeris-shell [-q] <target> <method> [args]` wraps `qs ipc -p …/aeris/shell.qml call`. Targets
are declared as `IpcHandler` blocks in `shell.qml`:

| Target | Methods |
|---|---|
| `bar` | `toggle` (hide/show), `refresh` (re-run every StatusModule) |
| `dock` | `reveal`, `conceal`, `flip` (`show`/`hide` are reserved `qs ipc` words) |

A new target is a new `IpcHandler` in `shell.qml` that writes to `Shell` state; widgets bind to
that state rather than being called directly.

## Theme and configuration

`Commons/Theme.qml` holds the defaults. `~/.config/aeris/shell.json` overrides any key and is
watched, so an edit applies at once:

```json
{ "version": 1, "colors": { "fg": "#ffffff", "dim": "#808080" }, "fonts": { "size": 13 } }
```

`version: 1` is required; anything else is ignored with a warning in the log. There is no deep
merge: a missing key falls back to the default, a present key wins. Keep configuration to things
a person would change without opening QML; widget order is QML.

## Editing and verifying

```bash
pkill -x qs; qs -p ~/.config/quickshell/aeris/shell.qml > /tmp/shell.log 2>&1 &   # relaunch
grep -vE ' INFO' /tmp/shell.log                                                   # QML errors
aeris-shell bar refresh && aeris-shell dock reveal                                # IPC answers
grim -g "0,0 1600x40" /tmp/bar.png                                                # look at it
cp -a ~/.config/quickshell/aeris dotfiles/home/.config/quickshell/                # into the repo
```

Edit the live tree under `~/.config/quickshell/aeris/` and copy it into `dotfiles/` (or run
`./setup.sh snapshot`), or edit the repo copy and `./setup.sh dotfiles`; do not let the two drift.
Hyprland autostarts the shell, so a login also relaunches it. A QML error shows in the log and
leaves the previous shell running only if you kill it after the new one is confirmed up; the
sequence above kills first, so read the log before walking away.

Widget files contain Nerd Font glyphs as raw characters. Make targeted edits around them; an
editor or tool that normalises Unicode can strip them.

## Open tasks

- Fold `aeris-orbit` (a separate `qs -p` popup with the ISS/Tiangong map) into this process as
  `Bar/OrbitPopup.qml`, reading `Status` instead of its own FileView, so the alerts pill opens it
  through `Shell` state instead of spawning a process.
- The lock screen (`lock/make-hyprlock`) and the login theme (`sddm/aeris/`) render their own
  copies of the status cards. A shared card definition is the next step if cards keep multiplying.

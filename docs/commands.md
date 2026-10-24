# Commands

Every AerisOS command is one executable file in `bin/`. `./setup.sh tools` installs them all
into `~/.local/bin`, which is on `PATH`. The installed name is the filename: `dnd`,
`screenshot`, `aeris-update`. Names are an interface (Hyprland binds, the bar, the menu,
OpenCode permissions call them), so a rename is a change to every caller.

## The header

The router reads a comment header in the first 12 lines of each file, directly under the shebang:

```bash
#!/bin/bash
# aeris:summary=Do Not Disturb: state for the bar, or toggle
# aeris:group=toggle
# aeris:args=[toggle]
# Do Not Disturb (dunst). `dnd toggle` flips it; `dnd` prints Waybar JSON (hidden when off).

set -euo pipefail
```

| Key | Required | Meaning |
|---|---|---|
| `summary` | yes | One line, shown in listings. A file without it is not a command as far as the router is concerned. |
| `group` | yes | One of the groups below. |
| `args` | no | Usage arguments, shown by `--help`. |
| `hidden` | no | `true` keeps it out of the default listing: timers, helpers called by the bar or the lock screen. |

Python scripts put the same `#` lines between the shebang and the docstring. Node scripts use
`//`. The free comment lines after the header are the description `aeris <command> --help` prints.

## Groups

| Group | Holds |
|---|---|
| `toggle` | On/off switches with a bar icon: `dnd`, `nightlight`, `stay-awake` |
| `capture` | `screenshot`, `screenrecord` |
| `display` | `display-scale`, `screen-off`, `make-mono-icons` |
| `system` | `aeris-menu`, `aeris-update`, `keybinds`, `aeris`, the battery timers |
| `intel` | `aeris-watch`, `aeris-inbox`, `watch-open`, `aeris-alerts`, `aeris-onto` |
| `voice` | `aeris-speak`, `aeris-hello`, `aeris-announce`, `aeris-agent-notify` |
| `net` | `tailscale-status` |
| `desktop` | The shell and lock-screen helpers: `aeris-shell` (IPC to the bar and dock), `aeris-greeting`, `aeris-lock-field` |

A new group is a line in `GROUP_DESC` in `bin/aeris`. Prefer an existing one.

## The router

`bin/aeris` scans its own directory, so it works from the checkout and from `~/.local/bin`.

```
aeris                     every visible command, by group
aeris list                the same including hidden ones
aeris list --json         machine-readable: route, file, group, hidden, args, summary
aeris toggle              one group
aeris dnd toggle          runs dnd with "toggle"; the route is the filename minus "aeris-"
aeris update --help       prints the header and description; never runs the command
```

Two files that resolve to the same route (say `aeris-watch` and a future `watch`) make the
router exit with an error naming both, so a collision cannot go unnoticed.

## Conventions a command follows

- Bash: `#!/bin/bash`, `set -euo pipefail`, see `AGENTS.md`. A deliberate departure is
  written on the `set` line itself.
- Bar output is Waybar JSON, `{"text": "...", "class": "on|off|...", "tooltip": "..."}`,
  and the command exits 0 even when it has nothing to show (empty `text` hides the module).
- A command that changes what the bar displays pushes the refresh itself:
  `aeris-shell -q bar refresh` (quiet: no error when the shell is not running).
- Anything that needs root says so in its description and is run by the user from a terminal.

## Adding a command

1. Create `bin/<name>`, executable, with the header. Pick the group.
2. Run `bash test/commands-test.sh` (header, shebang, strict mode, route collision).
3. Install it: `./setup.sh tools`, or for one file `install -m755 bin/<name> ~/.local/bin/`.
4. Wire callers: `hyprland.lua` for a key, the bar QML for an icon, `vicinae/aerisos/src/menu.tsx`
   for a menu row. Then `./setup.sh snapshot` so `dotfiles/` carries the config change.
5. If the user should know it exists, one row in the README's Shortcuts or Customising table.

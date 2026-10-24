# AerisOS: how this repository is written

The contract for anyone, person or agent, changing code here. `~/AGENTS.md` is a different
document: the map of the running system (where data lives, what thresholds mean). Keep the
two apart: this file says how, that one says where. Reference material is in `docs/`, user
documentation is the `README.md`.

## Layout

| Path | Job |
|---|---|
| `bin/` | Every AerisOS command, one executable per file, installed to `~/.local/bin` by `./setup.sh tools`. Nothing else goes here: no units, no data. |
| `bin/aeris` | The router. `aeris` lists commands by group, `aeris <command>` runs one, `aeris <command> --help` describes it. |
| `status/` | The collector `aeris-status` (root, systemd timer) and its units. The only code that calls external APIs. |
| `lock/`, `sddm/aeris/` | Lock and login screens. Renderers of `status.json` and `lock.tsv`; they make no network calls. |
| `dotfiles/home/` | Configs restored into `$HOME` by `./setup.sh dotfiles` and captured by `./setup.sh snapshot`. The Quickshell bar and dock QML live here. |
| `battery/`, `t2/`, `iso/`, `plymouth/`, `vicinae/` | One module each, named for what it sets up. |
| `setup.sh` | The installer. One `mod_<name>()` per module, idempotent, backs up before overwriting. |
| `docs/` | Reference for people working on the code. `docs/README.md` is the index. |
| `test/` | `./test/run` runs every `test/*-test.sh`. |

## Shell scripts

- `#!/bin/bash`, never `#!/usr/bin/env bash` or `#!/bin/sh`. Python is `#!/usr/bin/env python3`.
- `set -euo pipefail` right after the header comment. A script that must keep going past
  failures says so on the `set` line, as `aeris-update` does.
- Bash 5 conditionals: `[[ ]]` for strings and files, `(( ))` for numbers. Variables unquoted
  inside `[[ ]]`, string literals quoted: `[[ $state == "Running" ]]`, `(( capacity <= 7 ))`.
- A full `if`/`else` for two-path flow. Do not rely on `exit` in one branch.
- Quote paths that may contain spaces; never escape the space.
- Two-space indent in new scripts. Existing four-space files stay as they are until rewritten.
- Helpers over raw commands when one exists: the shell is reached with `aeris-shell`
  (`aeris-shell -q bar refresh`), the voice is `aeris-speak`, the alert summary is
  `aeris-alerts`. Do not reimplement them inline.

## Commands

- Every file in `bin/` carries a header the router reads (`docs/commands.md`):
  `# aeris:summary=`, `# aeris:group=`, optionally `# aeris:args=` and `# aeris:hidden=true`.
  Node scripts use `//` instead of `#`. The header sits directly under the shebang, before
  the description comment or docstring.
- Installed names are an interface. `dnd`, `screenshot`, `stay-awake` and the rest are called
  from `hyprland.lua`, the bar QML, the Vicinae menu and OpenCode permissions. Do not rename
  an installed command without updating every caller in the same change
  (`grep -rn '<name>' dotfiles vicinae README.md`).
- A command prints for the bar in Waybar JSON (`{"text","class","tooltip"}`) and exits 0 even
  when the thing it reports is absent. The bar shows nothing for an empty `text`.
- A command that changes state the bar shows ends by pushing a refresh. The bar's own timer
  is the fallback, not the mechanism.
- Root-owned deployments are explicit: `sudo install -m755 status/aeris-status /usr/local/bin/aeris-status`
  after editing the collector. There is no passwordless sudo; ask the user to run it.

## The shell (Quickshell)

- One long-running process, `~/.config/quickshell/aeris/shell.qml`: `Commons/` singletons
  (`Theme`, `Status`, `Shell`), `Ui/` shared components, `Bar/` one file per widget, `Dock/`.
  New UI is a file in that tree, never a second `qs -p`. Commands reach it with `aeris-shell`.
  How to write a widget, get data in and verify a change: `docs/shell.md`.
- Colors, fonts and sizes come from `Theme` (defaults in `Commons/Theme.qml`, user overrides
  in `~/.config/aeris/shell.json`, watched). No literal colors or font names in widgets.
- React to events. Order of preference: a Quickshell service that signals (`UPower`,
  `Pipewire`, `Hyprland`, `SystemTray`), a `FileView { watchChanges: true }` on the file that
  holds the state, a push over IPC from the command that changed it, and only then a `Timer`.
  A timer that runs a process needs a comment saying why no signal exists, and an interval
  of 60 s or more unless the panel it feeds is open.
- `status.json` and `lock.tsv` are the contract between the collector and every renderer.
  Add a field to the collector first, then read it; never fetch from a renderer.

## Tests

- `./test/run` runs everything and keeps each file's log. Run one file directly while
  working: `bash test/commands-test.sh`.
- A test earns its place by naming the regression it would catch. None for a config value,
  a string, a menu row or a rename. None that greps for the line just added. A test must fail
  without the change it guards.
- Pure logic lives in a function and is tested without the desktop: `gnss_status()` in the
  collector, the router's scan. Anything that needs the compositor or the network is checked
  by hand in the running session.
- Extend the existing `*-test.sh` for the area before adding a file.

## Documentation

- `README.md` is for the user of the machine: what a module installs, which key does what.
  Never internals.
- `docs/` is for whoever edits the code: file layout, the command contract, testing, the
  status pipeline. Link to it from here rather than repeating it.
- `~/AGENTS.md` (in `dotfiles/home/`) is the system map. Update it when a data location,
  threshold or pipeline changes, in the same commit.
- Full lines in Markdown, no hard wrapping inside a paragraph except at structural breaks.

## Git

- Atomic commits: one coherent change each. Message says what changed and, when it is not
  obvious, why. The repo is private; it contains a licensed font and machine details.
- After changing anything the snapshot captures, run `./setup.sh snapshot` so `dotfiles/`
  matches the machine, and commit that too.

# What AerisOS can learn from Omarchy Quattro

Studied 2026-10-24 against `omacom/omarchy`, branch `quattro`, commit `02defc5` (version `4.0.0.alpha`).
Sources: the repo itself (`AGENTS.md`, `docs/`, `agents/skills/`, `shell/`, `bin/`, `test/`), the manual
chapter `manual/32-shell-plugins.md`, and plugins.omarchy.org/develop.html.

The point of this document is not to copy Omarchy. It is a single-maintainer distro with a packaging
pipeline, ARM platforms, i18n and a marketplace, none of which AerisOS has or needs. The point is to
extract the habits that make the codebase pleasant to work in and cheap to change, and to decide which
of them fit a one-machine, one-person system with an agent as co-maintainer.

---

## 1. How the repository is organized

### 1.1 Every top-level directory has one job

| Directory | Job | Ships in package? |
|---|---|---|
| `bin/` | Every runtime command, 539 of them, all named `omarchy-*`, plus the `omarchy` router | yes |
| `config/` | Default user configs, copied verbatim to `~/.config/` on a new user | yes |
| `default/` | System-side defaults and theme templates (`default/themed/*.tpl` with `{{ var }}` placeholders) | yes |
| `etc/` | Drop-ins the distro owns outright under `/etc` | yes |
| `shell/` | The Quickshell desktop: `Commons/`, `Ui/`, `services/`, `plugins/` | yes |
| `install/` | Sourced setup "leaves", no shebangs, orchestrated by `all.sh` files | yes |
| `migrations/` | One-shot repair scripts named by unix timestamp, no shebang, `0644` | yes |
| `themes/` | `colors.toml` + optional `shell.toml` per theme | yes |
| `test/` | `cli`, `shell`, `all` runners and `shell.d/*-test.sh` (506 files) | no |
| `docs/` | Reference for people working on the code: shell architecture, file layout, update pipeline, testing | no |
| `agents/skills/` | Task procedures for whoever edits the code, agent or human | no |
| `manual/` | End-user documentation, published; never internals | no |
| `plans/` | Design notes for unbuilt features | no |

`docs/file-layout.md` maps every repo path to its installed path. Nothing lands on the machine
without a row there.

### 1.2 Three documentation trees, split by genre and audience

This is the single most reusable idea. AGENTS.md states it in three lines:

- `agents/skills/` is **procedure**: "read this before doing X". Short, imperative, one file per kind of work
  (command metadata, install scripts, migrations, shell dev, visual verification, acceptance tests).
- `docs/` is **reference**: how the system is shaped. Skills link here for depth.
- `manual/` is **user documentation**. It never mentions codebase internals.

`CLAUDE.md` is one line: `@AGENTS.md`. There is no separate human and agent contract.
A `.greptile/files.json` maps each doc to the glob of files it governs, so a reviewer (bot or person)
loads exactly the rules that apply to the diff.

### 1.3 AGENTS.md is a contract, not a map

Omarchy's AGENTS.md is 15 KB of rules with reasons: shell style, naming, which helpers to call instead
of raw commands, when a test is worth writing, how to run tests without wasting runs, the
polling ban. It is the thing a new contributor reads first and the thing a reviewer cites.

AerisOS's `~/AGENTS.md` is a **system map** (where data lives, what thresholds mean). That is valuable
and should stay, but it answers "where is it" and never "how do we write it". The two genres want
separate files.

---

## 2. Shell-script standards

Every rule below is enforced either by the test suite or by review. All are cheap to adopt.

1. **One shebang.** `#!/bin/bash`, never `#!/usr/bin/env bash`. 516 of 539 commands use it. The thirteen
   `#!/bin/bash -p` files are security entrypoints, each with a comment explaining why and a regression test.
2. **`set -euo pipefail`** at the top of every executable command. Sourced leaves omit it and the shebang because
   the orchestrator sets them.
3. **Bash 5 conditionals.** `[[ ]]` for strings and files, `(( ))` for numbers. Unquoted variables inside `[[ ]]`,
   quoted literals: `[[ $branch == "dev" ]]`, `(( count < 50 ))`.
4. **Full `if`/`else`** for two-path flow. Never rely on `exit` in one branch to make later lines unreachable.
5. **Quote paths with spaces**, never backslash-escape them.
6. **Two-space indent, no tabs**, LF, final newline (`.editorconfig`).
7. **A `fail()` helper** that prefixes the command name and exits 1. Every `omarchy-plugin-*` script starts with it.
8. **`interactive()`** = `[[ -t 0 && -t 1 ]]`. Prompts only when interactive; otherwise refuse with a message
   naming the flag (`--yes`) that skips the prompt. Scripts and agents get a deterministic path.
9. **Helpers over raw commands.** `omarchy-pkg-add` not `pacman -S`, `omarchy-notification-send` not
   `notify-send`, `omarchy-hw-*` predicates not `uname -m`. Each helper is the one place a policy lives.
10. **No defensive `command -v` around invariants.** If a package is in the base set, call its binary.
    Presence checks are only for genuinely optional tools.
11. **Privilege line.** `sudo` when a terminal can take a password, `pkexec` only when there is none. Never
    poll a privileged probe (`sudo -n` writes to the auth log).
12. **Atomic commits**, short messages describing the change.

---

## 3. The command layer

### 3.1 One router, flat binaries

`bin/omarchy` is a bash router. It scans the first 80 lines of every `omarchy-*` file for metadata
comments and builds routes from the filename:

```bash
# omarchy:summary=Add a shell plugin from git
# omarchy:group=plugin
# omarchy:args=[git-url] [--enable] [--yes]
# omarchy:examples=omarchy plugin add https://github.com/acme/omarchy-weather.git --enable
# omarchy:alias=omarchy plugin install
```

So `omarchy plugin add` and `omarchy-plugin-add` are the same thing. `omarchy` alone lists groups
from a `GROUP_DESCRIPTIONS` table in the router. `omarchy <group>` lists that group's commands with
their summaries. `--help` never executes the target. A metadata lint in `test/cli` fails the suite when a
command lacks a summary or uses a retired key.

Why it works: discoverability comes for free from naming, help text lives next to the code, and the
binaries stay plain files you can run, read with `cat $(which ...)`, and test in isolation.

### 3.2 Prefix groups

Prefixes encode purpose, not subsystem: `hw-` predicates return exit codes for conditionals, `toggle-`
flips a feature, `refresh-` copies a default config into `~/.config` with a backup, `restart-` restarts a
component, `launch-` opens an app, `install-`/`remove-` for optional software, `dev-` for repo tooling.
The authoritative list is the router table, deliberately not duplicated in prose.

---

## 4. The shell and its plugin system

### 4.1 One process

`omarchy-shell` is a single Quickshell instance. Bar, panels, overlays, menu, lock screen, polkit
agent, notifications, OSD and headless services are all plugins inside it. `agents/skills/shell-dev.md`
says it in one sentence: do not start additional standalone Quickshell instances for individual
components. The reasons are shared state (theme, services, IPC), one restart command, and memory.

### 4.2 Layers inside `shell/`

| Layer | Lines | Contents |
|---|---|---|
| `Commons/` | ~2.5k | Singletons: `Color`, `Style`, `Border`, `Util`, `I18n`, `ShellIpc`, `IpcRegistry` |
| `Ui/` | ~5k | Reusable components: `BarWidget`, `WidgetButton`, `Panel`, `KeyboardPanel`, `PanelKeyCatcher`, `Button`, `Dropdown`, `Toggle`, `TextField`, `PopupCard` |
| `services/` | ~2k | `PluginRegistry`, `BarWidgetRegistry`, `AppLibrary`, and the `Plugin*Api` facades |
| `plugins/` | ~46k | Everything the user sees |

The framework is a tenth of the code. Plugins never import each other.

### 4.3 The manifest contract

```json
{
  "schemaVersion": 1,
  "id": "omarchy.weather",
  "name": "Weather",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": { "displayName": "Weather", "category": "Info", "allowMultiple": false, "defaultSection": "centerEnd" }
}
```

Six kinds: `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `service`. A manifest may declare several.
Entry points are QML `Item`s, never `ShellRoot`. Validation (`PluginRegistry.validateManifest`, mirrored
by `omarchy plugin validate` and by `test/shell.d/plugins-test.sh`) checks the schema version, required
fields, an id with no `/` or `..`, a non-empty kinds array, an entry point for every kind, each entry point
a relative path that exists and stays inside the plugin folder, and no symlinks anywhere in the folder.
Validation is the same code path at install time, load time and test time.

### 4.4 Dependency injection, not singletons

From `shell.qml`:

> Plugins receive these via property injection rather than re-importing them as singletons.
> Relative-path imports do not share singleton state, which silently leaves consumers with their own empty copies.

The host injects `shell`, `omarchyPath`, `manifest`, `pluginRegistry`, `barWidgetRegistry` as properties.
A bar widget gets `bar` (foreground, background, fontFamily, position, `run(cmd)`, tooltip and popout
requests) and `settings` (its inline JSON entry). Widgets bind to these rather than reading them once,
because they change in place when a widget is dragged to another section.

### 4.5 Trust is a property of the manifest's origin

First-party plugins get the real host objects. Third-party plugins get capability-scoped facades
(`services/Plugin*Api.qml`) that can look up only their own service and lifecycle. Authentication
services are kept out of the public service map and the QML object tree entirely. The docs are honest
that this is an API boundary, not a sandbox: a visual widget can still walk its parent chain.

### 4.6 Configuration rules worth stealing

- **One file, no deep merge.** `~/.config/omarchy/shell.json` is canonical once it exists. Otherwise
  `config/omarchy/shell.json` is used verbatim. A built-in fallback inside `shell.qml` renders a usable
  bar even if both are missing. `version: 1` is required.
- **Enabled means present.** A third-party plugin is on when its id appears in the file. First-party
  non-bar plugins are on unless listed in `disabledPlugins[]`. So a stock config never silently disables
  shell infrastructure, and the file only records deviations.
- **Settings inline on the entry.** `{ "id": "omarchy.clock", "format": "HH:mm" }`. No `config:`
  sub-object, no layers.
- **Theme tokens in a separate file** (`shell.toml`) answering a different question. A machine-level
  override is watched live and wins over the theme's.
- **Both files are watched** with `FileView { watchChanges: true }`. Edits apply without a restart.

### 4.7 Clone, don't edit

`omarchy plugin clone omarchy.clock` copies the built-in to `~/.config/omarchy/plugins/<user>.clock`,
renames it, enables it, and records `omarchy.clonedFrom`. Calls to the original id route to the clone.
Removing the clone restores the built-in. Saving any file under the plugins directory hot-reloads.
This is how users customize without touching package-owned files, and how the next update cannot
overwrite their work.

### 4.8 Logic in `.js`, UI in `.qml`

Every non-trivial plugin pairs `Something.qml` with `SomethingModel.js`. The `.js` file ends with:

```js
if (typeof module !== "undefined") {
  module.exports = { batteryPercentage, isDischarging, shouldWarnLowBattery, ... }
}
```

QML imports it and ignores the guard. Node loads it as CommonJS. About a quarter of the test files
unit-test parsing, merging and layout logic this way with no compositor. `BatteryModel.js` is a 50-line
example: pure functions taking device state in and returning `{ level, notify, notifiedLowBattery }`.

### 4.9 IPC is the API

`bin/omarchy-shell <target> <method> [args]` is the one way a CLI talks to the running shell. It forwards
and fails if the shell is not running (`-q` for quiet best-effort). Targets are named for the plugin, not
where it appears. The `shell` target has `summon`, `hide`, `toggle`, `call`, `rescanPlugins`,
`reloadConfig`, `listPlugins`, `setPluginEnabled`. Every command that changes state the shell displays
ends with `omarchy-shell -q <target> refresh`.

### 4.10 Events, not polling

From AGENTS.md: long-running code reacts to events; polling is the last resort for state with no change
signal. `shell-dev.md` gives the ladder:

1. A native Quickshell service that signals: `UPower`, `PowerProfiles`, `Hyprland`, `Pipewire`, `Mpris`,
   `SystemTray`, `Notifications`.
2. An event stream the shell already runs (Hyprland IPC, one `pactl subscribe`). Extend it, do not start a second.
3. A file watch (`FileView` with `watchChanges`).
4. A push from the command that changes the state (`omarchy-shell -q target refresh`). For a change
   that happens later with no command running, a transient `systemd-run --user --on-active=` timer.
5. Only then a timer, gated on the panel being open, in one shared service, never per monitor.

`test/shell.d/shell-idle-spawn-test.sh` starts a second shell with a preloaded exec logger and fails if
it spawns any process over 30 idle seconds. The rule has teeth.

---

## 5. Testing philosophy

Three runners. `./test/cli` is one script owning the router and metadata lint. `./test/shell` runs
every `test/shell.d/*-test.sh` in a job pool, keeps every log, continues past failures and prints
the log directory. `./test/all` runs both and reports failed suites. Acceptance tests run in a VM and are
excluded on purpose.

The base contract is forty lines: `pass`, `skip`, `fail` (prints `not ok` and exits the file),
`require_command`, `require_compositor` (probes the socket and asks Hyprland, because an inherited
`WAYLAND_DISPLAY` proves nothing in a sandbox), and `run_node_test`. Fake `$HOME`, real `$ROOT`,
XDG variables unset so a test cannot reach the real home. Stub the world in a scratch `bin/`, run the
real script, grep the call log.

The rules about **when** to write a test are the valuable part:

- A test earns its place only by catching a regression nothing else would. Name the breakage first.
- No test for a declarative change (menu row, config value, string, rename).
- Do not restate the implementation or grep for the string you just added.
- A test must fail without the change.
- Do not test your own stub.
- No change-detectors (snapshots, exact counts, file lists).
- Extend the area's existing file instead of adding one.
- No test for a migration. It runs once and is frozen. Move the logic to a command and test that.
- Run tests to a log file and read the log. Never pipe through `head`/`tail`. Never rerun hoping it passes.

Performance guards compare counts, not wall-clock where possible, and scale budgets by a measured
fork/exec speed so a Raspberry Pi gets room and a regression still fails.

---

## 6. Migrations

`migrations/<unix-timestamp>.sh`: no shebang, `0644`, starts with an `echo` of what it does, idempotent,
runs as the user with `bash -euo pipefail`, per-user marker in `~/.local/state/omarchy/migrations/`.
Strictly ordered: a migration that cannot finish exits non-zero and stops the queue. Run by
`omarchy update`, and a login notifier offers to run pending ones in a terminal. Never silently in the
background. `omarchy-dev-add-migration` creates the file.

The useful idea for a one-machine system: state changes to `$HOME` are scripts with a marker, not
instructions in a README, so the same change applies on the second machine without rediscovery.

---

## 7. Install and defaults

Three layers populate `$HOME`: **seed** (`/etc/skel` at user creation), **finalize** (per-user runtime
step for things needing `$HOME` expansion or detection), **resync** (`omarchy-reinstall-configs`,
explicitly destructive). `omarchy-refresh-config <relative-path>` copies one default back with a
timestamped backup. Install leaves are sourced, use `$OMARCHY_PATH`, avoid `exit`, and are gated by
`omarchy-hw-*` predicates rather than `uname`.

---

## 8. Where AerisOS stands today

Honest comparison, same categories.

| Area | Omarchy | AerisOS now |
|---|---|---|
| Shell processes | one (`omarchy-shell`) | two `qs` instances (bar, dock) plus hyprlock and SDDM theme |
| Bar structure | plugins with manifests, `Ui/` components | one 559-line `shell.qml`, modules inline, an inline `StatusModule` component |
| Data refresh | events; idle shell spawns nothing | 7 `StatusModule`s each run a shell script every 10 s; network every 3 s; dock-autohide runs `hyprctl cursorpos` every 150 ms and `hyprctl monitors` + python every 5 s |
| Commands | 539 `omarchy-*` in `bin/`, one router, metadata headers | `aeris-*` split between `~/aerisos/bin/` (6) and `~/.local/bin/` (~30), no router, no help convention, `.bak` files beside live ones |
| Shebangs | one form | five forms across 53 scripts |
| `set -euo pipefail` | everywhere | 16 of ~30 bash scripts |
| Config | `shell.json` canonical, watched, versioned | constants at the top of QML files; README says "edit colors `bg`/`fg`/`dim`/`warn` at the top" |
| Tests | 506 shell tests, CLI lint, idle guard | none |
| Docs | contract + reference + procedure + manual, four trees | one 400-line README plus `~/AGENTS.md` system map |
| Updates to `$HOME` | migrations with markers | `install.sh`/`setup.sh` and the dotfiles copier with backups |
| Status pipeline | n/a | `aeris-status` writes `status.json` on a timer; consumers poll it |

Two things AerisOS already does the Omarchy way: the dotfiles copier backs up before overwriting, and
the status collector builds the formatted rows once and publishes them to both lock and login screens
so they cannot drift. Keep both.

---

## 9. Recommendations

Ordered by payoff per hour. Tier 1 is a day of work and needs no architecture change.

### Tier 1: adopt now

1. **Split `~/AGENTS.md` into a contract and a map.** Keep the system map as is. Add a short
   `CONTRIBUTING`-style contract at the top of the repo (`AGENTS.md` in `~/aerisos`, imported by
   `CLAUDE.md` with one line) with the shell rules in section 2, the "events not polling" rule, the
   test rules, and where each kind of file goes. Four hundred words is enough to start.
2. **One shebang, one preamble.** `#!/bin/bash` and `set -euo pipefail` in every executable bash script.
   `#!/usr/bin/env python3` stays for Python. Delete the `.bak` files from `~/.local/bin` (they are in git).
3. **Gather the commands.** Move every `aeris-*` script into `~/aerisos/bin/` as the source of truth and
   let the dotfiles copier install them. Add a metadata header to each (`# aeris:summary=`, `# aeris:args=`)
   and a 60-line `aeris` router that lists them. `aeris` with no argument becomes the system's help page.
   Helpers that are not user-facing (`dock-autohide`, `tailscale-status`) get `# aeris:hidden=true`.
4. **Push, don't poll, where the signal already exists.** Toggle scripts (`dnd`, `nightlight`, `stay-awake`,
   `screenrecord`) already know when state changes. End each with
   `qs ipc -p <bar> call bar refresh` and drop their 10 s timers. The bar already has `refreshTick`; this
   just makes it the primary path instead of the fallback.
5. **A `docs/` directory.** This file is the first entry. The next two are the status pipeline reference
   (move it out of `~/AGENTS.md` and link to it) and the T2 recovery story (currently in the README).

### Tier 2: structural, a weekend each

6. **Split the bar into files.** `Commons/` (colors, fonts, `Style`), `Ui/` (`StatusModule`, `Pill`,
   `Expander`, the Tailscale popup card), `widgets/<name>/Widget.qml` + `Model.js`. Same single process,
   same IPC, but each widget is a folder. This is the precondition for everything below.
7. **Move the dock into the bar process.** The dock is a 100-line `PanelWindow` with three IPC methods.
   As a `service` inside the bar's process it shares theme and font, and `dock-autohide` loses the
   "is it still running" loop. Then replace the 150 ms cursor poll: Quickshell has `Hyprland` events and
   a layer-shell window can own its own hover region, so the reveal is an edge hit on a 2 px strip rather
   than a shell loop calling `hyprctl`.
8. **`~/.config/aeris/shell.json`.** Colors, fonts, which widgets in which order, status card thresholds.
   `FileView { watchChanges: true }`, canonical once present, built-in fallback in QML. Stop asking
   people to edit QML constants.
9. **Model.js with the CommonJS guard, plus `test/shell.d/`.** Start with the two places that have real
   logic: GNSS classification (the `nac_p` thresholds in `aeris-status`) and the near-duplicate story
   collapse in the watch feed. Both are pure functions today in Python; the test harness can be
   `test/shell.d/base-test.sh` copied nearly verbatim with `run_node_test` swapped for a Python
   equivalent. Add the forty-line base file and two test files. Nothing more until a bug justifies it.
10. **Status as a watched file, not a timer.** `aeris-status` already writes `status.json` atomically.
    Every consumer (bar pill, OpenCode board, lock screen generator) should watch the file instead of
    re-reading on its own timer. In QML that is one `FileView`. The systemd timer stays the only clock.

### Tier 3: an AerisOS plugin system

Only worth doing after 6 to 8, and only if AerisOS will run on more than one machine or if the status
cards keep multiplying. The design that fits, borrowing the parts that pay for themselves and skipping
the rest:

- **One process, `aeris-shell`**, launched by Hyprland, restarted by `aeris restart shell`.
- **A plugin is a folder with `manifest.json`.** First-party under `~/aerisos/shell/plugins/`, user
  plugins under `~/.config/aeris/plugins/<id>/`. Same validation function in the registry and in
  `aeris plugin validate`.
- **Four kinds, not six.** `bar-widget`, `panel`, `service`, and one Omarchy does not have: `card`, a
  status-board tile that renders a slice of `status.json` and declares which key it reads
  (`"card": { "source": "air.gnss", "alert": "JAMMED" }`). Lock screen, login screen and the OpenCode board
  can then render the same card list from the same manifests, which is the drift-free property the
  collector already has for feed rows, extended to cards.
- **Injection over singletons**: the host hands each entry point `shell`, `settings`, `status`
  (the parsed `status.json`) and `bar`. Widgets bind, never copy.
- **Enabled means present** in `shell.json`; first-party on unless in `disabledPlugins[]`.
- **IPC target per plugin**, named for the plugin. `aeris-shell <target> <method>` as the one CLI path.
- **Clone-a-builtin** is worth having even for one person: it is the difference between editing a file
  the repo owns and editing a copy the dotfiles copier will not overwrite.
- **Skip**: the trust facades (single user, you wrote every plugin), i18n, the marketplace, `bar` as a
  replaceable kind, `menu` and `overlay` kinds until there is a second consumer.

### What not to copy

- The migration machinery as built. A one-machine system wants `aeris update` to run idempotent
  `migrations/*.sh` with a marker directory, and that is thirty lines, not a notifier service.
- Hardware platform predicates. There is one machine family; the DMI-keyed rule in `hyprland.lua` is
  the right size.
- The acceptance-test VM. Visual verification by looking at the screen is proportionate here.

---

## 10. The five sentences to remember

1. Documentation has three genres (procedure, reference, user manual) and they do not share files.
2. Every command is a flat file with a metadata header; the router and the help page are derived from that.
3. Long-running code reacts to events, and a test fails if an idle shell spawns anything.
4. A plugin is a folder with a manifest, validated by one function used at install, load and test time.
5. A test earns its place by naming the regression it catches, and a declarative change gets none.

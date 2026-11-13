# AerisOS developer reference

Reference for whoever edits this repository. The user manual is `../README.md`; the rules for
writing code are `../AGENTS.md`; the map of the running system is `~/AGENTS.md`. These pages
hold the detail those three link to.

| Page | What it covers |
|---|---|
| [commands.md](commands.md) | The `bin/` contract: metadata header, groups, the `aeris` router, installing, adding a command |
| [testing.md](testing.md) | `./test/run`, the `base-test.sh` contract, when a test is worth writing |
| [shell.md](shell.md) | The Quickshell process: where a widget goes, the singletons, how data gets in (events over polling), IPC targets, theme overrides, how to edit and verify |
| [monologue.md](monologue.md) | Monologue camera recorder: the 0.3.1 encoder failures (QSV frame loss, NVENC refusal, slow x264), what 0.4.0 fixed, the wrapper and shim, building from omarchy-pkgs |
| [omarchy-study.md](omarchy-study.md) | What was borrowed from Omarchy Quattro and what was deliberately not |

Pages still to write, in the order they are needed: the status pipeline (collector, caches,
`status.json` and `lock.tsv` schema, who reads what) and the T2 recovery story (currently in
the README).

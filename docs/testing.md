# Testing

```
./test/run                   every test/*-test.sh, logs kept, summary at the end
bash test/commands-test.sh   one file while working on that area
```

## The contract

Every test file starts the same way:

```bash
#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
```

`base-test.sh` refuses to be executed directly. It exports `ROOT` (the checkout) so tests
reference `$ROOT/bin/...` and never depend on the working directory or on what is installed
in `~/.local/bin`. It unsets the XDG base directories so a test that points `HOME` at a
scratch directory cannot reach the real home through them.

Assertions are TAP-flavored and blunt:

- `pass "description"` prints `ok - description`.
- `skip "description"` prints `ok - description # SKIP`, with the reason in the description.
- `fail "description" [detail]` prints the detail and `not ok - description`, then exits the
  file. The first failure ends the file; the runner continues with the next file and lists
  the failures with their log paths at the end.
- `require_command <cmd>` fails the file when a tool is missing.
- `run_python_test <<'PY' ... PY` runs the heredoc with `python3 -I`, with `ROOT` in the
  environment and `pass`, `fail`, `assert_equal`, `load_script(relative_path)` defined.
  `load_script` imports a file that has no `.py` extension, such as `status/aeris-status`,
  as a module, so its functions can be called without running `main()`.

## When to write one

A test earns its place by catching a regression nothing else would. Before writing one, name
the breakage. Then:

- No test for a declarative change: a config value, a menu row, a package in a list, a string.
- Do not restate the implementation or grep for the line just added.
- The test must fail without the change. Revert the fix in your head and check it goes red.
- Do not test your own stub. If a fake binary provides the behaviour under test, nothing real is tested.
- No snapshots of large output or exact counts that break on unrelated additions.
- Extend the area's file instead of adding one. New files are for new areas.
- Keep it proportionate: a few lines of change rarely need more than a few lines of test.

Do test real logic: parsing, classification thresholds, routing, the edge case a fix handles.

## Stub the world, run the real code

A test that would touch the desktop builds a scratch `bin/` of stub executables that log
their arguments, prepends it to `PATH`, and runs the real script. The assertion reads the log.
`commands-test.sh` does this to prove `aeris <command> --help` never executes the command.
Anything that genuinely needs the compositor or the network is checked by hand in the
running session, not in `test/`.

## Files

| File | Guards |
|---|---|
| `commands-test.sh` | Every `bin/` file has the header, the shebang and strict mode; routes do not collide; the router lists and describes without executing |
| `gnss-test.sh` | The GNSS jamming thresholds in `aeris-status` (`gnss_status()`): surface targets excluded, one bad contact is OK, two is LOW, three with more than 10% share is JAMMED |

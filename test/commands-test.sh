#!/bin/bash
# The bin/ contract (docs/commands.md): header, shebang, strict mode, the router.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

BIN="$ROOT/bin"
commands=()
for f in "$BIN"/*; do
  [[ -f $f && -x $f ]] && commands+=("$f")
done
(( ${#commands[@]} > 0 )) || fail "bin/ holds executable commands"

# --- every command declares itself -------------------------------------------------------
for f in "${commands[@]}"; do
  name=$(basename -- "$f")
  head -n 12 -- "$f" | grep -qE '^(#|//) aeris:summary=.+' ||
    fail "$name has an aeris:summary header in its first 12 lines"
  head -n 12 -- "$f" | grep -qE '^(#|//) aeris:group=[a-z]+$' ||
    fail "$name has an aeris:group header"
  shebang=$(head -n 1 -- "$f")
  case $shebang in
    '#!/bin/bash')
      grep -qE '^set -[a-z]+' "$f" || fail "$name (bash) sets strict mode" ;;
    '#!/usr/bin/env python3' | '#!/usr/bin/env node') ;;
    *) fail "$name uses an approved shebang" "found: $shebang" ;;
  esac
done
pass "every command has a header, an approved shebang and (bash) strict mode"

# --- no stray shebang forms elsewhere in the repo ---------------------------------------
stray=$(grep -rlE '^#!/usr/bin/env bash|^#!/bin/sh$' "$ROOT"/setup.sh "$ROOT"/install.sh "$ROOT"/games-drive.sh \
  "$ROOT"/iso/build.sh "$ROOT"/t2/*.sh "$ROOT"/lock "$ROOT"/status "$ROOT"/battery 2>/dev/null || true)
[[ -z $stray ]] || fail "no script uses env bash or sh" "$stray"
pass "setup, install, iso and t2 scripts use #!/bin/bash"

# --- the router -------------------------------------------------------------------------
require_command python3
listing=$("$BIN/aeris") || fail "aeris with no arguments exits 0"
json=$("$BIN/aeris" list --json) || fail "aeris list --json exits 0"

# Every executable with a header is routed, under the filename minus the aeris- prefix
for f in "${commands[@]}"; do
  name=$(basename -- "$f")
  route=${name#aeris-}; [[ $name == aeris ]] && route=aeris
  python3 -I -c 'import json,sys; sys.exit(0 if any(r["route"]==sys.argv[1] and r["file"]==sys.argv[2] for r in json.load(sys.stdin)) else 1)' \
    "$route" "$name" <<<"$json" || fail "aeris list --json routes $name as '$route'"
done
pass "every command is routed by its filename minus the aeris- prefix"

# Hidden commands stay out of the default listing and in the full one
hidden_route=$(python3 -I -c 'import json,sys; print(next(r["route"] for r in json.load(sys.stdin) if r["hidden"]))' <<<"$json")
grep -qE "^  $hidden_route " <<<"$listing" && fail "hidden command '$hidden_route' is absent from the default listing"
full=$("$BIN/aeris" list) || fail "aeris list exits 0"
grep -qE "^  $hidden_route " <<<"$full" || fail "hidden command '$hidden_route' appears in aeris list"
pass "hidden commands are listed only by aeris list"

# A route collision is refused, naming both files
dir=$(scratch_dir)
cp -- "$BIN/aeris" "$BIN/dnd" "$dir/"
cp -- "$BIN/dnd" "$dir/aeris-dnd"
if out=$("$dir/aeris" 2>&1); then
  fail "aeris refuses two files on one route" "$out"
fi
grep -q "claimed by both" <<<"$out" || fail "the collision message names both files" "$out"
pass "two files on one route make the router exit with an error"

# --help describes without running: dnd would call dunstctl
stubs=$(scratch_dir)
stub "$stubs" dunstctl "false"
stub "$stubs" qs ""
help=$(PATH="$stubs:$PATH" "$BIN/aeris" dnd --help) || fail "aeris dnd --help exits 0"
grep -q "Do Not Disturb" <<<"$help" || fail "aeris dnd --help prints the summary" "$help"
[[ ! -e $stubs/calls.log ]] || fail "aeris dnd --help does not run dnd" "$(cat "$stubs/calls.log")"
pass "aeris <command> --help describes the command without executing it"

# An unknown name is an error, not a silent exit
if "$BIN/aeris" no-such-command >/dev/null 2>&1; then
  fail "aeris rejects an unknown command"
fi
pass "an unknown command exits non-zero"

#!/bin/bash
# Shared test library. Source it; do not run it. See docs/testing.md.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source test/base-test.sh from a test file; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

# Tests point HOME at a scratch directory; a desktop session also exports the XDG base
# directories, which would keep pointing at the real home. Unset, they follow HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'ok - %s # SKIP\n' "$1"
}

fail() {
  local description=$1 detail=${2:-}
  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null || fail "required command is available: $1"
}

# A scratch directory removed when the file exits. Usage: dir=$(scratch_dir)
SCRATCH_DIRS=()
scratch_dir() {
  local d
  d=$(mktemp -d -t aeris-test.XXXXXX)
  SCRATCH_DIRS+=("$d")
  printf '%s\n' "$d"
}
cleanup_scratch() {
  local d
  for d in "${SCRATCH_DIRS[@]}"; do rm -rf -- "$d"; done
}
trap cleanup_scratch EXIT

# A stub executable at $1/$2 that appends its name and arguments to $1/calls.log and
# prints $3 (optional). Prepend $1 to PATH to make the real script under test call it.
stub() {
  local dir=$1 name=$2 output=${3:-}
  mkdir -p -- "$dir"
  cat >"$dir/$name" <<SH
#!/bin/bash
printf '%s %s\n' "$name" "\$*" >>"$dir/calls.log"
printf '%s' '$output'
SH
  chmod +x "$dir/$name"
}

# Runs the heredoc on stdin with python3 -I. The prelude mirrors the bash protocol and adds
# load_script(path) for files without a .py extension (the collector, for one).
run_python_test() {
  require_command python3
  {
    cat <<'PY_PRELUDE'
import importlib.machinery, importlib.util, os, sys
ROOT = os.environ["ROOT"]

def pass_(description):
    print(f"ok - {description}")

def fail(description, detail=""):
    if detail:
        print(detail, file=sys.stderr)
    print(f"not ok - {description}", file=sys.stderr)
    sys.exit(1)

def assert_equal(actual, expected, description):
    if actual != expected:
        fail(description, f"expected: {expected!r}\nactual:   {actual!r}")
    pass_(description)

def load_script(relative_path, name=None):
    path = os.path.join(ROOT, relative_path)
    name = name or os.path.basename(path).replace("-", "_")
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module

PY_PRELUDE
    cat
  } | python3 -I -
}

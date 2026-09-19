# Shared test helpers. Sourced by every test file.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/consilium/scripts"
# Always the system bash when present: on macOS that is 3.2, the oldest we support.
BASH_BIN="${BASH_BIN:-$([ -x /bin/bash ] && echo /bin/bash || command -v bash)}"

FAILED=0
fail() { echo "  FAIL: $1" >&2; FAILED=1; }
assert_contains()     { grep -Fq -- "$2" "$1" 2>/dev/null || fail "$1 should contain: $2"; }
assert_not_contains() { grep -Fq -- "$2" "$1" 2>/dev/null && fail "$1 should NOT contain: $2"; return 0; }
assert_file()         { [ -s "$1" ] || fail "missing or empty: $1"; }

# A throwaway project directory with a clean environment.
new_project() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/consilium-test.XXXXXX")"
  ( cd "$d" && git init -q . )
  echo "$d"
}
clean_env() {
  unset CM_REVIEWERS CM_ARBITERS CM_VERIFIERS CM_IMPLEMENTERS CM_HOST CM_LANG CM_OUT_DIR \
        CM_SKIP_REVIEWERS CM_SKIP_VERIFIERS CM_CONFIG CM_ADAPTERS_DIR CM_PROJECT_DIR \
        CM_MOCK_MODE CM_ATTEMPTS CM_ONLY_FIRST_MODEL
  export CM_DISABLE_NOTIFICATIONS=1 CM_WATCH_INTERVAL=1 CM_RETRY_DELAY=0
  export XDG_CONFIG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/consilium-xdg.XXXXXX")"
}
# Replace every <!-- TODO ... --> in a brief so the launch guard lets it through.
fill_brief() {
  python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"<!-- TODO.*?-->", "filled in by the test", s))
PY
}
finish() { if [ "$FAILED" = 0 ]; then echo "PASS: $1"; else echo "FAILED: $1" >&2; exit 1; fi; }

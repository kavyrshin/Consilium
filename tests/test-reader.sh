#!/usr/bin/env bash
# The local reader: serves the case tree and markdown, refuses paths outside the cases
# folder (including through symlinks), foreign Host headers, and, in --public mode,
# requests without the password. Skipped when Node.js is not installed.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
clean_env
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "SKIP: curl not installed"; exit 0; }

P="$(new_project)"
mkdir -p "$P/consilium/2026-01-01-demo"
printf '# Brief\n' > "$P/consilium/2026-01-01-demo/brief.md"
printf '> **DRAFT**\n' > "$P/consilium/2026-01-01-demo/decision.md"
printf 'secret\n' > "$P/outside.md"
ln -s "$P/outside.md" "$P/consilium/2026-01-01-demo/link.md"
PORT=$(( 20000 + RANDOM % 20000 ))
READER_PID=""
stop() {
  if [ -n "$READER_PID" ]; then
    kill "$READER_PID" 2>/dev/null || true
    wait "$READER_PID" 2>/dev/null || true
  fi
  READER_PID=""
}
trap stop EXIT
start() {  # start [extra args...]
  (cd "$P" && exec "$BASH_BIN" "$S/reader.sh" --port "$PORT" "$@") > "$P/reader.log" 2>&1 &
  READER_PID=$!
  local i
  for i in $(seq 1 50); do grep -qi "consilium reader:" "$P/reader.log" 2>/dev/null && return 0; sleep 0.1; done
  fail "reader did not start: $(cat "$P/reader.log")"
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
U="http://127.0.0.1:$PORT"

start
curl -s "$U/api/tree" | grep -q '"brief.md"' || fail "tree does not list brief.md"
[ "$(curl -s "$U/api/tree" | python3 -c 'import json,sys; t=json.load(sys.stdin); print([f["name"] for f in t["dirs"][0]["files"]])')" = "['brief.md', 'decision.md']" ] || fail "files not in pipeline order, or a symlink was listed"
[ "$(curl -s "$U/api/file?path=2026-01-01-demo/brief.md")" = "# Brief" ] || fail "cannot read a case file"
[ "$(code "$U/api/file?path=../outside.md")" = 404 ] || fail "path traversal not refused"
[ "$(code "$U/api/file?path=2026-01-01-demo/link.md")" = 404 ] || fail "symlink out of the cases folder not refused"
[ "$(code -H 'Host: evil.example' "$U/")" = 403 ] || fail "foreign Host header accepted (DNS rebinding)"
[ "$(code "http://localhost:$PORT/")" = 200 ] || fail "localhost Host refused"
curl -sI "$U/" | grep -qi "content-security-policy: default-src 'none'" || fail "no CSP on the page"
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -q '127.0.0.1' || fail "not bound to 127.0.0.1 only"
fi
stop

CM_READER_PASSWORD="correct-horse-battery" start --public
[ "$(code -H 'Host: x.ngrok.app' "$U/api/tree")" = 401 ] || fail "public mode served without a password"
[ "$(code -H 'Host: x.ngrok.app' -u consilium:wrong-password-x "$U/api/tree")" = 401 ] || fail "public mode accepted a wrong password"
[ "$(code -H 'Host: x.ngrok.app' -u consilium:correct-horse-battery "$U/api/tree")" = 200 ] || fail "public mode refused the right password"
curl -s -H 'Host: x.ngrok.app' -u consilium:correct-horse-battery "$U/" | grep -q "ROOT_ABS = \"\"" || fail "public mode leaks the local path"
stop

CM_READER_PASSWORD="short" start --public 2>/dev/null || true
grep -q "at least 12" "$P/reader.log" || fail "weak password accepted"
finish "reader: tree, files, traversal and symlink refusal, host check, public mode auth"

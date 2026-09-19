#!/usr/bin/env bash
# Starts the local reader for this project's consilium cases: a read-only web page on
# http://localhost:4600 that lists every case and renders its documents, updating live as
# reviewers and arbiters write. Runs in the foreground; Ctrl+C stops it.
#
#   reader.sh [--port N] [--open] [--public]
#
# --open    also opens the page in the default browser.
# --public  to share through a tunnel (e.g. `ngrok http 4600`): requires a password,
#           printed at start (or set CM_READER_PASSWORD, 12+ characters).
# Needs Node.js 18+. Listens on 127.0.0.1 only. Port: --port or CM_READER_PORT.

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PORT="${CM_READER_PORT:-4600}"
OPEN=0
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --port) shift; PORT="${1:?--port needs a number}" ;;
    --open) OPEN=1 ;;
    --public) EXTRA+=(--public) ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$PORT" in ''|*[!0-9]*) echo "consilium: --port must be a number" >&2; exit 2 ;; esac

if ! command -v node >/dev/null 2>&1; then
  echo "consilium: the reader needs Node.js 18+ (https://nodejs.org). The case files are plain markdown in $(cm_rel "$CONSILIUM")/ and can be read with anything." >&2
  exit 1
fi

if [ "$OPEN" = 1 ]; then
  URL="http://localhost:$PORT"
  # Give the server a moment to bind before the browser asks for the page.
  ( sleep 1
    if command -v open >/dev/null 2>&1; then open "$URL"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
    fi ) >/dev/null 2>&1 &
fi

# "${EXTRA[@]+...}" keeps bash 3.2 happy with an empty array under set -u.
exec node "$CM_SKILL_DIR/reader/reader.cjs" "$CONSILIUM" --port "$PORT" --lang "$CM_LANG" ${EXTRA[@]+"${EXTRA[@]}"}
exit
}

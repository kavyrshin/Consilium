#!/usr/bin/env bash
# Background watcher: waits until a case's reviews are in, then runs write-decision.sh.
#
#   watch-and-decide.sh <case-dir> [timeout-seconds, default 14400]
#
# Normally started by run-reviewers.sh, not by hand.
#
# Exit condition: the host's review (<CM_HOST>-review.md) must exist, and every external
# reviewer must have either written its file or left .runners/<name>.done. Then the
# decision is synthesized from whoever answered, without waiting for the rest: one dead
# endpoint or an exhausted subscription must not leave the user with no document.
# The timeout stays as a backstop (a manual, hand-pasted reviewer signals nothing).

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CASE_ARG="${1:?usage: watch-and-decide.sh <case-dir> [timeout-seconds]}"
TIMEOUT="${2:-14400}"
cm_need_case "$CASE_ARG"
LOG_FILE="$CASE_DIR/.watch.log"
HOST_REVIEW="$CASE_DIR/$CM_HOST-review.md"

log() { echo "$(date '+%F %T') $1" >> "$LOG_FILE"; }

# Whom to wait for. Test for the file's EXISTENCE, not for non-emptiness: an empty file
# means "no external reviewers were started", and replacing that with the full default
# panel would make the watcher wait forever for people nobody launched.
EXPECTED_FILE="$CASE_DIR/.runners/expected"
if [ -f "$EXPECTED_FILE" ]; then
  EXPECTED="$(tr '\n' ' ' < "$EXPECTED_FILE")"
else
  EXPECTED=""
  for name in $CM_REVIEWERS; do [ "$name" = "$CM_HOST" ] || EXPECTED="$EXPECTED $name"; done
fi

log "watcher started, pid $$, timeout ${TIMEOUT}s, waiting for: $CM_HOST (host) +${EXPECTED:- nobody else}"

ELAPSED=0
INTERVAL="${CM_WATCH_INTERVAL:-10}"
PENDING=" ($CM_HOST-review.md)"
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  if cm_written "$HOST_REVIEW"; then
    PENDING=""
    for r in $EXPECTED; do
      if cm_written "$CASE_DIR/$r-review.md"; then continue; fi
      if [ -f "$CASE_DIR/.runners/$r.done" ]; then continue; fi
      PENDING="$PENDING $r"
    done
    if [ -z "$PENDING" ]; then
      log "everyone accounted for, synthesizing decision.md"
      if bash "$CM_SKILL_DIR/scripts/write-decision.sh" "$CASE_DIR" >> "$LOG_FILE" 2>&1; then
        log "watcher done: decision.md drafted"
      else
        log "watcher done: synthesis failed, see .logs/decision-*.log"
      fi
      exit 0
    fi
  fi
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# Timed out. If anything was written, synthesize anyway: half a document beats silence.
log "timeout ${TIMEOUT}s reached, still waiting for:$PENDING"
if cm_written "$HOST_REVIEW"; then
  log "host review present - synthesizing from what is there"
  if bash "$CM_SKILL_DIR/scripts/write-decision.sh" "$CASE_DIR" >> "$LOG_FILE" 2>&1; then
    log "watcher done: decision.md drafted (on timeout)"
  else
    log "watcher done: synthesis on timeout failed"
  fi
  exit 0
fi
log "host review never appeared - nothing to synthesize, giving up"
exit
}

#!/usr/bin/env bash
# Runs ONE external reviewer (an adapter) against a case and writes
# <adapter>-review.md. Normally started by run-reviewers.sh, but can be run by hand:
#
#   run-reviewer.sh <adapter> [case-dir|substring]
#
# The result is judged by the file's content, not the CLI's exit code: exit codes of
# these tools are unreliable. Leaves .runners/<adapter>.done = ok|fail so the watcher
# does not wait out its timeout for a reviewer that already failed.

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ADAPTER="${1:?usage: run-reviewer.sh <adapter> [case-dir]}"
cm_need_case "${2:-}"
REVIEW_FILE="$ADAPTER-review.md"
REVIEW="$CASE_DIR/$REVIEW_FILE"
LOG="$CASE_DIR/.logs/review-$ADAPTER.log"

if ! REASON="$(cm_check "$ADAPTER")"; then
  echo "consilium: $ADAPTER unavailable: $REASON - skipping this reviewer." >&2
  cm_mark_done "$CASE_DIR" "$ADAPTER" fail
  exit 1
fi

export CM_ROLE=reviewer CM_TARGET_FILE="$REVIEW" CM_FIRST_LINE=""
review_prompt() { CM_PROMPT="$(cm_prompt_review "$REL_CASE" "$REVIEW_FILE" "$1" "$2")"; }
review_ok() { cm_written "$REVIEW"; }

echo "Case: $REL_CASE - $ADAPTER ($(cm_first_model "$ADAPTER")) ..."
if cm_invoke "$ADAPTER" "$CM_PROJECT" "$CM_REVIEW_TIMEOUT" "$LOG" review_prompt review_ok; then
  echo "Done: $REL_CASE/$REVIEW_FILE (model: $CM_USED_MODEL)."
  cm_mark_done "$CASE_DIR" "$ADAPTER" ok
  exit 0
fi

# Fallback: some agents answer on stdout instead of using their write tool. If the last
# attempt printed something shaped like a review, keep it rather than lose the answer.
if [ "$(cm_stdout_fallback "$ADAPTER")" = 1 ]; then
  LAST="$(awk '/^=== /{buf=""; next} /^--- retry /{next} {buf=buf $0 "\n"} END{printf "%s", buf}' "$LOG")"
  if printf '%s' "$LAST" | grep -q '^## '; then
    {
      echo "# $(cm_label "$ADAPTER") $CM_L_REVIEW_WORD ($CM_USED_MODEL): $(basename "$CASE_DIR")"
      echo
      echo "$CM_L_STDOUT_NOTE"
      echo
      printf '%s\n' "$LAST"
    } > "$REVIEW"
    echo "Done: $REL_CASE/$REVIEW_FILE (model: $CM_USED_MODEL, via stdout fallback)."
    cm_mark_done "$CASE_DIR" "$ADAPTER" ok
    exit 0
  fi
fi

REASON="$(cm_failure_reason "$ADAPTER" "$LOG")"
echo "consilium: $ADAPTER did not write a review${REASON:+: $REASON}. Log: $(cm_rel "$LOG")" >&2
cm_mark_done "$CASE_DIR" "$ADAPTER" fail
exit 1
exit
}

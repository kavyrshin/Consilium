#!/usr/bin/env bash
# Stand-in for a real agent CLI, used by the `mock` adapter and by the tests.
# usage: mock-agent.sh <mode>
# The framework exports CM_ROLE, CM_TARGET_FILE, CM_FIRST_LINE and CM_LIVE_FILE so the
# mock knows what to write; real agents get the same information in their prompt.
#   success  write the expected artifact
#   fail     write nothing, exit 1
#   hang     sleep (to exercise timeouts)
#   delete   remove the protected decision file and the candidate, then exit 1
#            (reproduces an arbiter that deletes a file it was told not to touch)
#   stdout   print the artifact to stdout instead of writing the file

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODE="${1:-success}"
ROLE="${CM_ROLE:-reviewer}"
TARGET="${CM_TARGET_FILE:-}"

body() {
  case "$ROLE" in
    reviewer)
      printf '# Mock %s (mock-1): mock topic\n\n' "$CM_L_REVIEW_WORD"
      printf '%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n' \
        "$CM_R1" "$CM_R2" "$CM_R3" "$CM_R4" "$CM_R5" "$CM_R6" ;;
    arbiter)
      printf '%s\n\nMock restatement of the question. MOCK_ARBITER_OUTPUT\n\n' "${CM_FIRST_LINE:-}"
      printf '%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\n%s\n\n%s\nMock text.\n' \
        "$CM_D1" "$CM_D2" "$CM_D3" "$CM_D4" "$CM_D5" "$CM_D_NOT_RUN" "$CM_D6" ;;
    verifier)
      printf '# Mock verifier (mock-1)\n\n%s\naccept\n\n%s\nMock text.\n\n%s\nNone.\n\n%s\nMock text.\n\n%s\nMock text.\n' \
        "$CM_V1" "$CM_V2" "$CM_V3" "$CM_V4" "$CM_V5" ;;
    implementer)
      printf '# Mock implementer report\n\n%s\nNothing changed (mock).\n\n%s\nMock text.\n\n%s\nMock text.\n\n%s\nMock text.\n' \
        "$CM_I1" "$CM_I2" "$CM_I3" "$CM_I4" ;;
  esac
}

case "$MODE" in
  success) [ -n "$TARGET" ] && body > "$TARGET"; exit 0 ;;
  stdout)  body; exit 0 ;;
  fail)    echo "mock agent: simulated failure (usage limit reached)" >&2; exit 1 ;;
  hang)    sleep 30; exit 0 ;;
  delete)  rm -f "${CM_LIVE_FILE:-/nonexistent}" "$TARGET"; exit 1 ;;
  *)       echo "mock agent: unknown mode $MODE" >&2; exit 2 ;;
esac
exit
}

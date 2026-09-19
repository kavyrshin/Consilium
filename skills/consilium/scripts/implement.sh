#!/usr/bin/env bash
# Implementer for a confirmed decision. One script, two passes:
#
#   impl  first wave: make exactly the changes authorized in decision.md (section
#         "Authorized code changes"), nothing beyond
#   fix   second pass: fix what the verifiers found (<name>-impl-review.md, see verify.sh)
#
#   implement.sh <case-dir|substring> <workdir> [impl|fix]
#
# The implementer is the first available adapter in CM_IMPLEMENTERS. It works in the
# given working tree (normally a git worktree on its own branch), never commits, never
# switches branches; that stays with the human. Its report is written into the case
# folder: impl-report.md / fix-report.md.
#
# About the working directory: some agent CLIs refuse to read files outside their cwd.
# The case lives in the project, so when the working tree is inside the project we run
# from the project root (both are visible); otherwise the case documents are copied
# into <workdir>/.consilium-context/ and the agent runs from the working tree.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cm_need_case "${1:?usage: implement.sh <case> <workdir> [impl|fix]}" decision.md
WORKDIR="$(cd "${2:?usage: implement.sh <case> <workdir> [impl|fix]}" && pwd -P)"
PASS="${3:-impl}"

# shellcheck disable=SC2086
ADAPTER="$(cm_available $CM_IMPLEMENTERS 2>/dev/null | head -1 || true)"
[ -n "$ADAPTER" ] || { echo "consilium: no implementer available (CM_IMPLEMENTERS='$CM_IMPLEMENTERS')" >&2; exit 1; }

case "$WORKDIR/" in
  "$CM_PROJECT/"*)
    RUN_DIR="$CM_PROJECT"
    CTX="$REL_CASE"
    REPORT_PATH="$CASE_DIR"
    ;;
  *)
    RUN_DIR="$WORKDIR"
    mkdir -p "$WORKDIR/.consilium-context"
    cp "$CASE_DIR"/*.md "$WORKDIR/.consilium-context/"
    CTX=".consilium-context"
    REPORT_PATH="$WORKDIR/.consilium-context"
    ;;
esac
if [ "$WORKDIR" = "$RUN_DIR" ]; then REL_WORK="."; else REL_WORK="${WORKDIR#"$RUN_DIR"/}"; fi
BRANCH="$(cm_branch "$WORKDIR")"

case "$PASS" in
  impl)
    REPORT="impl-report.md"
    TASK="You are the implementer for a consilium decision. Read ${CTX}/decision.md, especially the section '${CM_D6}' (the work order) and anything it marks as forbidden; read ${CTX}/brief.md and the reviews in ${CTX}/ for context when the decision references them. Make exactly the authorized changes, nothing beyond them; if an authorized change turns out impossible or wrong once you see the code, do not improvise a substitute - skip it and explain why in the report."
    ;;
  fix)
    REPORT="fix-report.md"
    TASK="You are the implementer for a consilium decision, doing the second pass. You already made the first wave of changes (see 'git -C ${REL_WORK} diff' and ${CTX}/impl-report.md). Verifiers reviewed it: read every ${CTX}/*-impl-review.md (any verifier may be missing if it failed). Also re-read ${CTX}/decision.md. Fix every defect the verifiers found that is within the authorized scope of decision.md. If the verifiers disagree, or a requested fix would go beyond what decision.md authorizes, do not apply it - list it in the report as '${CM_I_NOT_APPLIED}' with the reason, for the user to decide."
    ;;
  *) echo "consilium: unknown pass '$PASS' (expected impl or fix)" >&2; exit 1 ;;
esac

RULES="Work only inside ${REL_WORK} (a git working tree on branch ${BRANCH}). Do NOT commit, push, switch branches, stash or reset. Do not modify files outside ${REL_WORK} except the report file named below. Do not install packages. The working tree may already hold part of this work from an earlier interrupted attempt: inspect it first and do not duplicate or revert it. Keep the code style and comment language of the surrounding code (comments explain WHY). Verify your own work before finishing: at minimum a syntax check of every file you changed; if a runtime check is feasible, do it and quote the numbers."

export CM_ROLE=implementer CM_TARGET_FILE="$REPORT_PATH/$REPORT" CM_FIRST_LINE=""
# shellcheck disable=SC2059
impl_prompt() {
  local label="$1" model="$2" title
  title="$(printf "$CM_I_TITLE" "$label" "$model" "$PASS")"
  CM_PROMPT="${TASK} ${RULES} When done, write a short report in ${CM_LANG_NAME} to ${CTX}/${REPORT} with a level-1 heading '# ${title}', then sections: '${CM_I1}' (change -> file:lines -> essence), '${CM_I2}' (with numbers), '${CM_I3}', '${CM_I4}'."
}
report_ok() { [ -s "$REPORT_PATH/$REPORT" ]; }
# A report left by an earlier run must not be mistaken for the result of this one.
rm -f "$REPORT_PATH/$REPORT" "$CASE_DIR/$REPORT"

LOG="$CASE_DIR/.logs/implement-$PASS.log"
echo "Implementer: $(cm_label "$ADAPTER") ($(cm_first_model "$ADAPTER")), pass $PASS, tree $WORKDIR (branch $BRANCH) ..."
# Only the first model of a chain: a half-finished run may have edited files.
CM_ONLY_FIRST_MODEL=1 cm_invoke "$ADAPTER" "$RUN_DIR" "$CM_IMPLEMENT_TIMEOUT" "$LOG" impl_prompt report_ok || true
STATUS="${CM_LAST_STATUS:-0}"

# The agent may have written into the copied context; bring the report back to the case.
if [ "$CTX" = ".consilium-context" ] && [ -s "$REPORT_PATH/$REPORT" ]; then
  cp "$REPORT_PATH/$REPORT" "$CASE_DIR/$REPORT"
fi

if [ -s "$CASE_DIR/$REPORT" ]; then
  echo "Done (exit $STATUS): report $REL_CASE/$REPORT, log $(cm_rel "$LOG")"
  exit 0
fi

# No report: keep at least what the agent said on stdout.
{
  echo "# $(printf "$CM_I_TITLE" "$(cm_label "$ADAPTER")" "$CM_USED_MODEL" "$PASS")"
  echo
  echo "> _The implementer wrote no report (exit ${STATUS}); the tail of its output follows._"
  echo
  tail -n 80 "$LOG"
} > "$CASE_DIR/$REPORT"
echo "consilium: implementer wrote no report (exit $STATUS); saved the log tail as $REPORT" >&2
exit 1

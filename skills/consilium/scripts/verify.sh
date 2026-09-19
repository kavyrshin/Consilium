#!/usr/bin/env bash
# Verifies an implementation of a consilium decision: every available adapter in
# CM_VERIFIERS reviews the uncommitted working tree in parallel and independently,
# writing <name>-impl-review.md into the case folder. Verifiers never edit code; fixes
# come from the implementer's second pass (implement.sh <case> <workdir> fix).
#
#   verify.sh <case-dir|substring> <workdir>
#
# Waits for all verifiers (each has its own timeout) and succeeds if at least one wrote
# its review: one failed verifier must not block the fix pass.
# Skip someone: CM_SKIP_VERIFIERS="codex". Prefer verifiers other than the implementer.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cm_need_case "${1:?usage: verify.sh <case> <workdir>}" decision.md
WORKDIR="$(cd "${2:?usage: verify.sh <case> <workdir>}" && pwd -P)"
BRANCH="$(cm_branch "$WORKDIR")"

SKIP=" ${CM_SKIP_VERIFIERS:-} "
WANTED=""
for n in $CM_VERIFIERS; do
  case "$SKIP" in *" $n "*) continue ;; esac
  WANTED="$WANTED $n"
done
# shellcheck disable=SC2086
VERIFIERS="$(cm_available $WANTED 2>/dev/null | tr '\n' ' ' || true)"
[ -n "${VERIFIERS// /}" ] || { echo "consilium: no verifier available (CM_VERIFIERS='$CM_VERIFIERS')" >&2; exit 1; }

# shellcheck disable=SC2059
verify_prompt() {
  local label="$1" model="$2" file="$V_FILE" title
  title="$(printf "$CM_V_TITLE" "$label" "$model" "$BRANCH")"
  CM_PROMPT="You are an implementation verifier for a consilium decision. Do NOT modify any code; the only file you may write is ${REL_CASE}/${file}. Read ${REL_CASE}/decision.md (especially '${CM_D6}' and what it forbids), ${REL_CASE}/impl-report.md if present (the implementer's own report; do not trust its numbers, re-measure), and ${REL_CASE}/fix-report.md if present. The implementation is uncommitted in the git working tree ${WORKDIR} (branch ${BRANCH}): inspect it with 'git -C ${WORKDIR} diff'. Check: (A) exactly the authorized changes were made and nothing beyond them; (B) no prohibition was violated; (C) each change actually achieves its stated goal - verify with your own runtime measurements where feasible (syntax check, test run, script), quoting numbers; (D) no regression in previously fixed behaviour mentioned in the decision. Do not invent defects: if a change is correct, say so. Write the review in ${CM_LANG_NAME} to ${REL_CASE}/${file}, starting with the heading '# ${title}', then sections '${CM_V1}' (one line: ${CM_V_VERDICTS}), '${CM_V2}', '${CM_V3}' (each: where, what is wrong, impact, how to fix - this list is the work order for the implementer's second pass), '${CM_V4}', '${CM_V5}'. Other verifiers work in parallel; do not read any other *-impl-review.md before writing your own."
}

PIDS=()
NAMES=()
for name in $VERIFIERS; do
  rm -f "$CASE_DIR/$name-impl-review.md"   # never mistake an old review for this run's
  (
    V_FILE="$name-impl-review.md"
    export CM_ROLE=verifier CM_TARGET_FILE="$CASE_DIR/$V_FILE" CM_FIRST_LINE=""
    v_ok() { [ -s "$CASE_DIR/$V_FILE" ]; }
    CM_ATTEMPTS=1 cm_invoke "$name" "$CM_PROJECT" "$CM_VERIFY_TIMEOUT" "$CASE_DIR/.logs/verify-$name.log" verify_prompt v_ok
  ) > /dev/null 2>&1 &
  PIDS+=($!)
  NAMES+=("$name")
  echo "Started $(cm_label "$name") ($(cm_first_model "$name")), log $REL_CASE/.logs/verify-$name.log"
done

OK=0
i=0
for pid in "${PIDS[@]}"; do
  name="${NAMES[$i]}"
  i=$((i + 1))
  wait "$pid" || true
  if [ -s "$CASE_DIR/$name-impl-review.md" ]; then
    OK=$((OK + 1))
    echo "$name: $(grep -m1 -A2 "^$CM_V1" "$CASE_DIR/$name-impl-review.md" | tail -n +2 | tr -s '\n' ' ')"
  else
    reason="$(cm_failure_reason "$name" "$CASE_DIR/.logs/verify-$name.log")"
    echo "$name: no review written${reason:+ ($reason)}" >&2
  fi
done
[ "$OK" -gt 0 ]

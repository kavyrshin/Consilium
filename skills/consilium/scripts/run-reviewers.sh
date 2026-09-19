#!/usr/bin/env bash
# Launches every EXTERNAL reviewer of a case in parallel, in the background, plus one
# watcher that synthesizes decision.md when the reviews are in. Returns immediately.
#
#   run-reviewers.sh [case-dir|substring]     start the panel
#   run-reviewers.sh --plan                   only print who would run (and who would
#                                             be skipped and why); starts nothing
#
# The host agent (CM_HOST) is never launched here: it writes its own review by hand.
# Reviewers run in parallel because they are independent by construction; running them
# one after another would add up their times.
#
# Skip someone for one run: CM_SKIP_REVIEWERS="codex deepseek".
# Choose the panel:        CM_REVIEWERS="codex opencode".

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [ "${1:-}" = "--plan" ]; then
  echo "Host (writes its own review): $(cm_label "$CM_HOST")"
  PLAN="$(cm_plan_reviewers)"
  echo "External reviewers that would run: ${PLAN:-none}" | tr '\n' ' '; echo
  echo "Arbiters (draft decision):        $(cm_available $CM_ARBITERS 2>/dev/null | tr '\n' ' ' || true)"
  echo "Case folder:                      $(cm_rel "$CONSILIUM")/"
  echo "NOTE: each reviewer above receives the contents of your project files it reads; check where each provider sends data."
  exit 0
fi

cm_need_case "${1:-}"

# The brief is the only thing the reviewers get; a skeleton with unanswered TODOs would
# waste every model call on an empty question.
if grep -q '<!-- TODO' "$CASE_DIR/brief.md"; then
  echo "consilium: brief.md still has <!-- TODO --> markers. Fill in the question, facts, constraints and scope first." >&2
  exit 1
fi

mkdir -p "$CASE_DIR/.runners" "$CASE_DIR/.logs"
rm -f "$CASE_DIR/.runners"/*.done 2>/dev/null || true

LAUNCHED=()
for reviewer in $(cm_plan_reviewers); do
  nohup bash "$CM_SKILL_DIR/scripts/run-reviewer.sh" "$reviewer" "$CASE_DIR" \
    > "$CASE_DIR/.logs/runner-$reviewer.log" 2>&1 &
  disown 2>/dev/null || true
  LAUNCHED+=("$reviewer")
  echo "Started $reviewer (pid $!) - log: $REL_CASE/.logs/runner-$reviewer.log"
done

# The watcher learns from this file whom to wait for. An empty file is meaningful ("no
# external reviewers"), so it is never replaced by the full default panel.
# An empty array under `set -u` is an error in bash 3.2, hence the explicit branch.
if [ ${#LAUNCHED[@]} -eq 0 ]; then
  : > "$CASE_DIR/.runners/expected"
  echo "No external reviewer started (none configured, none available, or all skipped)." >&2
else
  printf '%s\n' "${LAUNCHED[@]}" > "$CASE_DIR/.runners/expected"
fi

if [ -z "${CM_SKIP_WATCHER:-}" ]; then
  nohup bash "$CM_SKILL_DIR/scripts/watch-and-decide.sh" "$CASE_DIR" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  echo "Watcher started (pid $!): it drafts decision.md once the reviews are in (log: $REL_CASE/.watch.log)."
fi
exit
}

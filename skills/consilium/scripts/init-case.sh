#!/usr/bin/env bash
# Creates a new consilium case folder with the full skeleton.
#
#   init-case.sh <slug> [title]
#
# <slug>  short kebab-case English name of the topic (2-4 words), e.g. cache-strategy
# title   human-readable title for the brief (defaults to the slug)
#
# Creates <out-dir>/<YYYY-MM-DD>-<slug>/ (a -2, -3 ... suffix is added if it exists)
# with brief.md (to be filled in by the host agent: it still contains <!-- TODO -->
# markers, and run-reviewers.sh refuses to start until they are gone), a placeholder
# review file for the host and for every reviewer that will run, a decision.md
# placeholder and an empty tasks.json. Prints the case directory on stdout.
#
# The date comes from the system clock (CM_DATE overrides it, for tests): a model's
# idea of "today" is often stale.

# The whole script is one block, so bash parses it completely before running anything:
# updating the skill (git pull, a --symlink install) during a long run cannot make
# bash resume in the middle of a changed line.
{
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SLUG="${1:?usage: init-case.sh <slug> [title]}"
TITLE="${2:-$SLUG}"
case "$SLUG" in
  *[!a-z0-9-]*|-*|*-|'') echo "consilium: slug must be kebab-case (a-z, 0-9, hyphens): '$SLUG'" >&2; exit 1 ;;
esac

DATE="${CM_DATE:-$(date +%F)}"
mkdir -p "$CONSILIUM"
CASE_DIR="$CONSILIUM/$DATE-$SLUG"
n=2
while [ -e "$CASE_DIR" ]; do CASE_DIR="$CONSILIUM/$DATE-$SLUG-$n"; n=$((n + 1)); done
mkdir -p "$CASE_DIR"

# Keep run artefacts out of version control, if the project uses it.
if [ ! -f "$CONSILIUM/.gitignore" ]; then
  printf '%s\n' '.runners/' '.logs/' '.watch.log' '.decision-candidate.*/' '.consilium-context/' > "$CONSILIUM/.gitignore"
fi

# "Label (model)" for the roles line. "default" models are left out.
describe() {
  local name="$1" label model
  label="$(cm_label "$name")"
  model="$(cm_first_model "$name")"
  if [ -n "$model" ] && [ "$model" != default ]; then echo "$label ($model)"; else echo "$label"; fi
}
join_described() {
  local out="" name
  for name in "$@"; do out="${out}${out:+, }$(describe "$name")"; done
  echo "${out:-$CM_L_NONE}"
}

REVIEWERS="$(cm_plan_reviewers 2>/dev/null || true)"
# shellcheck disable=SC2086
ARBITERS="$(cm_available $CM_ARBITERS 2>/dev/null | head -2 | tr '\n' ' ' || true)"
# shellcheck disable=SC2086
IMPLEMENTER="$(cm_available $CM_IMPLEMENTERS 2>/dev/null | head -1 || true)"
# shellcheck disable=SC2086
VERIFIERS="$(cm_available $CM_VERIFIERS 2>/dev/null | tr '\n' ' ' || true)"

# shellcheck disable=SC2086
ROLES="$(printf "$CM_L_ROLES_FMT" \
  "$(cm_label "$CM_HOST") ($CM_L_HOST_TAG)${REVIEWERS:+, $(join_described $REVIEWERS)}" \
  "$(join_described $ARBITERS)" \
  "$(join_described $IMPLEMENTER)" \
  "$(join_described $VERIFIERS)")"

REVIEW_HEADINGS="$CM_R1
$CM_R2
$CM_R3
$CM_R4
$CM_R5
$CM_R6"

TEMPLATE="$CM_SKILL_DIR/templates/$CM_LANG/brief.md"
[ -f "$TEMPLATE" ] || TEMPLATE="$CM_SKILL_DIR/templates/en/brief.md"
cm_render "$TEMPLATE" "TITLE=$TITLE" "DATE=$DATE" "ROLES=$ROLES" "REVIEW_HEADINGS=$REVIEW_HEADINGS" > "$CASE_DIR/brief.md"

review_skeleton() {
  # shellcheck disable=SC2059
  printf "$CM_L_REVIEW_PLACEHOLDER\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n" "$1" "$CM_R1" "$CM_R2" "$CM_R3" "$CM_R4" "$CM_R5" "$CM_R6"
}
for name in $CM_HOST $REVIEWERS; do
  review_skeleton "$(cm_label "$name")" > "$CASE_DIR/$name-review.md"
done

printf '%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n' \
  "$CM_L_DECISION_PLACEHOLDER" "$CM_D1" "$CM_D2" "$CM_D3" "$CM_D4" "$CM_D5" "$CM_D6" "" > "$CASE_DIR/decision.md"

# Task list, filled in only after the decision exists.
# Item schema: id, description, owner, status, decision_ref.
printf '{\n  "tasks": []\n}\n' > "$CASE_DIR/tasks.json"

echo "consilium: created $(cm_rel "$CASE_DIR")" >&2
echo "$CASE_DIR"
exit
}

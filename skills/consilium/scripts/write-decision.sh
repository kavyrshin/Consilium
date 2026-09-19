#!/usr/bin/env bash
# Synthesizes a DRAFT decision.md for a case from brief.md and every review written so
# far. The synthesis is joint, in two passes over one document:
#
#   pass 1  first arbiter writes a draft from scratch
#   pass 2  second arbiter reads the brief, the reviews and that draft and revises it;
#           where it disagrees it must state both positions under "Disagreements"
#           instead of silently overwriting (otherwise "joint" would degrade into
#           "last writer wins")
#
#   write-decision.sh <case-dir>
#
# Arbiters are the first two AVAILABLE adapters in CM_ARBITERS. Failure handling:
#   - first arbiter fails or is unavailable -> the second writes the draft alone;
#   - second arbiter fails                  -> the first arbiter's draft is kept;
#   - neither works                         -> no document, the script exits non-zero.
# The note about who is missing is written by THIS SCRIPT from facts on disk, never by
# a model: a model that is part of the panel could soften it, forget it, or start
# judging how much the gap matters, i.e. speculating on behalf of someone who is absent.
#
# Both passes write to a candidate file, not to the live decision.md, and the candidate
# is published only after its structure has been validated. (An arbiter once deleted the
# live file and then lost its connection before writing the replacement.) The live file
# is also backed up and restored byte for byte if an arbiter touched it.
#
# The result is always a DRAFT with an explicit banner: the human is the final arbiter.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cm_need_case "${1:?usage: write-decision.sh <case-dir>}"
LIVE="$CASE_DIR/decision.md"
export CM_LIVE_FILE="$LIVE" CM_ROLE=arbiter

# ---- who reviewed, who did not -------------------------------------------------
# The roster is the host plus whoever was actually launched (falls back to the config
# when the case was not started through run-reviewers.sh).
ROSTER="$CM_HOST"
if [ -f "$CASE_DIR/.runners/expected" ]; then
  for n in $(cat "$CASE_DIR/.runners/expected"); do ROSTER="$ROSTER $n"; done
else
  for n in $CM_REVIEWERS; do [ "$n" = "$CM_HOST" ] || ROSTER="$ROSTER $n"; done
fi

PRESENT_LIST=""
MISSING_LIST=""
for n in $ROSTER; do
  if cm_written "$CASE_DIR/$n-review.md"; then
    PRESENT_LIST="${PRESENT_LIST}${PRESENT_LIST:+, }${REL_CASE}/$n-review.md"
  else
    MISSING_LIST="${MISSING_LIST}${MISSING_LIST:+, }$(cm_label "$n")"
  fi
done
if [ -z "$PRESENT_LIST" ] || ! cm_written "$CASE_DIR/brief.md"; then
  echo "consilium: no brief or no written reviews in $REL_CASE - nothing to synthesize" >&2
  exit 1
fi
echo "Reviews present: $PRESENT_LIST"
[ -n "$MISSING_LIST" ] && echo "Did not respond: $MISSING_LIST"

MISSING_CLAUSE=""
if [ -n "$MISSING_LIST" ]; then
  MISSING_CLAUSE=" These reviewers did NOT produce a review for this case (endpoint down, quota exhausted, or timed out): ${MISSING_LIST}. Do not speculate about what they would have said, and do not write anything about the panel being incomplete - a line stating that is added mechanically after you finish, and must not be duplicated."
fi

# ---- arbiters --------------------------------------------------------------------
WORK_DIR="$(mktemp -d "$CASE_DIR/.decision-candidate.XXXXXX")"
LIVE_BACKUP="$WORK_DIR/live-backup.md"
CAND="$WORK_DIR/candidate.md"
PASS1="$WORK_DIR/pass1.md"
cp -p "$LIVE" "$LIVE_BACKUP" 2>/dev/null || : > "$LIVE_BACKUP"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$CASE_DIR/.logs"

# The panel is the first two names configured; report those that cannot even start.
CONFIGURED="$(echo "$CM_ARBITERS" | tr -s ' ' '\n' | grep -v '^$' | head -2 | tr '\n' ' ' || true)"
ARBITER_MISSING=""
AVAILABLE=""
for n in $CONFIGURED; do
  if reason="$(cm_check "$n")"; then
    AVAILABLE="$AVAILABLE $n"
  else
    ARBITER_MISSING="${ARBITER_MISSING}${ARBITER_MISSING:+; }$(cm_label "$n"): unavailable (${reason:-unknown})"
  fi
done
# More than two configured: the next available ones step in when the first two are out.
if [ -z "${AVAILABLE// /}" ]; then
  # shellcheck disable=SC2086
  AVAILABLE="$(cm_available $CM_ARBITERS 2>/dev/null | head -2 | tr '\n' ' ' || true)"
fi
# shellcheck disable=SC2086
set -- $AVAILABLE
A1="${1:-}"
A2="${2:-}"
if [ -z "$A1" ]; then
  echo "consilium: no arbiter available (CM_ARBITERS='$CM_ARBITERS'): cannot synthesize" >&2
  cm_notify "Consilium: decision not drafted" "$REL_CASE - no arbiter available"
  exit 1
fi

HEADINGS="$CM_D1 / $CM_D2 / $CM_D3 / $CM_D4 / $CM_D5 / $CM_D6"

restore_live() {
  if ! cmp -s "$LIVE_BACKUP" "$LIVE" 2>/dev/null; then
    echo "An arbiter touched the protected decision.md - restoring it." >&2
    cp -p "$LIVE_BACKUP" "$LIVE"
  fi
}

# Valid = exactly the banner we asked for, and each of the six headings exactly once.
candidate_valid() {
  local file="$1" header="$2" heading count
  [ -s "$file" ] || return 1
  grep -Fqx "$header" "$file" || return 1
  for heading in "$CM_D1" "$CM_D2" "$CM_D3" "$CM_D4" "$CM_D5" "$CM_D6"; do
    count="$(grep -Fxc "$heading" "$file" 2>/dev/null || true)"
    [ "$count" = "1" ] || return 1
  done
}

# Per-pass state read by the prompt/check callbacks below.
PASS_MODE="" PASS_FIRST_LABEL="" PASS_FIRST_MODEL="" CM_EXPECT_HEADER=""

# shellcheck disable=SC2059
arb_prompt() {
  local label="$1" model="$2" rel_cand
  rel_cand="$(cm_rel "$CAND")"
  if [ "$PASS_MODE" = revise ]; then
    CM_EXPECT_HEADER="$(printf "$CM_L_DRAFT_JOINT" "$PASS_FIRST_LABEL" "$PASS_FIRST_MODEL" "$label" "$model")"
    cp "$PASS1" "$CAND"
    CM_PROMPT="Read ${REL_CASE}/brief.md, these reviews: ${PRESENT_LIST}, and ${rel_cand} - the first-pass synthesis written by ${PASS_FIRST_LABEL} (${PASS_FIRST_MODEL}). You are the second arbiter of a two-arbiter panel. Revise only ${rel_cand}, keeping its exact section structure (${HEADINGS}) and its language (${CM_LANG_NAME}). Do not edit ${REL_CASE}/decision.md or any other file. Use the supplied brief, reviews and draft as the evidence set; do not load unrelated skills. Your job is not to rewrite the draft in your own voice: keep what is correct, fix what is wrong or unsupported by the reviews, and add what is missing. Where you genuinely disagree with the first pass, do NOT silently overwrite it: state both positions in the '${CM_D2}' section, attributed ('first pass' vs 'second pass'), and make the '${CM_D3}' section say which way you land and why. Leave the '${CM_D5}' section as its placeholder - do not invent measurement results. Finally, replace the blockquote on the very first line so it reads exactly: ${CM_EXPECT_HEADER} Do not change anything else."
  else
    CM_EXPECT_HEADER="$(printf "$CM_L_DRAFT_SOLO" "$label" "$model")"
    printf '%s\n' "$CM_L_DECISION_PLACEHOLDER" > "$CAND"
    CM_PROMPT="Read ${REL_CASE}/brief.md and these reviews: ${PRESENT_LIST}. You are an arbiter of this consilium. Write the synthesis into ${rel_cand}, replacing its content entirely. Do not edit ${REL_CASE}/decision.md or any other file. Use the supplied brief and reviews as the evidence set; do not load unrelated skills. Use exactly this structure (headings verbatim, in ${CM_LANG_NAME}, each exactly once): ${HEADINGS}. The '${CM_D5}' section MUST be left as a short placeholder ('${CM_D_NOT_RUN}') - do not invent measurement results. The very first line of the file must be exactly: ${CM_EXPECT_HEADER}${MISSING_CLAUSE} Right after that line, before '${CM_D1}', add one short plain paragraph (1-2 sentences) restating the original question from the question section of brief.md in your own words. Be substantive, not a concatenation of the reviews: identify genuine points of agreement, genuine differences in coverage or position (say explicitly when one review found something the others missed, versus an actual disagreement - and when reviewers split, say which side the weight of evidence is on), a concrete decision with the rigor of a careful human arbiter, one falsifiable minimal experiment, and an explicit statement of which code changes are authorized right now versus deferred. The '${CM_D6}' section is the work order for the implementer, so make each change concrete (file, place, what exactly) and list what is forbidden. Attribute claims to the specific reviewer by the model name in that review file's heading. Write the whole document in ${CM_LANG_NAME}."
  fi
  export CM_TARGET_FILE="$CAND" CM_FIRST_LINE="$CM_EXPECT_HEADER"
}
arb_check() {
  restore_live
  candidate_valid "$CAND" "$CM_EXPECT_HEADER"
}

# Runs one arbiter pass. Returns 0 when a valid candidate exists in $CAND.
run_pass() {
  local name="$1"
  CM_ATTEMPTS=1 cm_invoke "$name" "$CM_PROJECT" "$CM_DECISION_TIMEOUT" "$CASE_DIR/.logs/decision-$name.log" arb_prompt arb_check
}

fail_reason() {
  local name="$1" log="$CASE_DIR/.logs/decision-$1.log"
  if [ "${CM_LAST_STATUS:-0}" -eq 124 ]; then echo "timed out after ${CM_DECISION_TIMEOUT}s"
  elif [ "${CM_LAST_STATUS:-0}" -ne 0 ]; then echo "exit ${CM_LAST_STATUS}: $(cm_failure_reason "$name" "$log")"
  else echo "output failed the structure check"
  fi
}

# Puts the fact-based panel note right under the banner. Runs AFTER both passes, not
# before: pass 2 rewrites the whole file and would otherwise lose it.
write_panel_note() {
  local note="$1"
  [ -n "$note" ] || return 0
  python3 - "$LIVE" "$note" <<'PYEOF'
import sys, pathlib
path, note = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = path.read_text(encoding="utf-8").split("\n")
# Re-running the synthesis replaces the old note instead of stacking a new one, and
# takes the blank line before it along so no empty paragraph accumulates.
kept = []
for line in lines:
    if line.startswith("_Incomplete panel:") or line.startswith("_Неполный состав:"):
        if kept and kept[-1] == "":
            kept.pop()
        continue
    kept.append(line)
lines = kept
at = next((i + 1 for i, l in enumerate(lines) if l.startswith(">")), 0)
lines[at:at] = ["", note]
path.write_text("\n".join(lines), encoding="utf-8")
PYEOF
}

# shellcheck disable=SC2059
panel_note() {
  local arbiter_missing="$1" parts=""
  [ -n "$MISSING_LIST" ] && parts="$(printf "$CM_L_NOTE_MISSING" "$MISSING_LIST")"
  if [ -n "$arbiter_missing" ]; then
    parts="${parts}${parts:+; }$(printf "$CM_L_NOTE_ARBITER" "$arbiter_missing")"
  fi
  [ -n "$parts" ] || return 0
  echo "${CM_L_NOTE_PREFIX} ${parts}. ${CM_L_NOTE_TAIL}"
}

publish() {
  cp "$CAND" "$LIVE"
  write_panel_note "$(panel_note "$ARBITER_MISSING")"
}

# ---- pass 1: first arbiter, from scratch ------------------------------------------
PASS1_OK=0
PASS_MODE=fresh
echo "Pass 1 - $(cm_label "$A1") drafts decision.md for $REL_CASE ..."
if run_pass "$A1"; then
  cp "$CAND" "$PASS1"
  PASS_FIRST_LABEL="$(cm_label "$A1")"
  PASS_FIRST_MODEL="$CM_USED_MODEL"
  PASS1_OK=1
  echo "Pass 1 done."
else
  R="$(fail_reason "$A1")"
  echo "Pass 1 ($(cm_label "$A1")) failed: $R" >&2
  ARBITER_MISSING="${ARBITER_MISSING}${ARBITER_MISSING:+; }$(cm_label "$A1"): $R"
fi

if [ "$PASS1_OK" = 1 ]; then
  if [ -z "$A2" ]; then
    publish
    echo "Done: $REL_CASE/decision.md - draft by one arbiter, needs your review."
    cm_notify "Consilium: decision.md ready" "$REL_CASE - draft awaits your review"
    exit 0
  fi
  # ---- pass 2: second arbiter revises ----
  PASS_MODE=revise
  echo "Pass 2 - $(cm_label "$A2") revises the draft ..."
  if run_pass "$A2"; then
    publish
    echo "Done: $REL_CASE/decision.md - joint draft of two arbiters, needs your review."
    cm_notify "Consilium: decision.md ready" "$REL_CASE - joint draft awaits your review"
    exit 0
  fi
  R="$(fail_reason "$A2")"
  echo "Pass 2 ($(cm_label "$A2")) failed: $R - keeping the first draft." >&2
  ARBITER_MISSING="${ARBITER_MISSING}${ARBITER_MISSING:+; }$(cm_label "$A2"): $R"
  cp "$PASS1" "$CAND"
  publish
  echo "Done: $REL_CASE/decision.md - draft by one arbiter ($(cm_label "$A1")), needs your review."
  cm_notify "Consilium: decision.md ready (one arbiter)" "$REL_CASE - $(cm_label "$A2") did not take part"
  exit 0
fi

# ---- first arbiter failed: second writes alone ------------------------------------
if [ -n "$A2" ]; then
  PASS_MODE=fresh
  echo "$(cm_label "$A2") drafts decision.md alone ..."
  if run_pass "$A2"; then
    publish
    echo "Done: $REL_CASE/decision.md - draft by one arbiter ($(cm_label "$A2")), needs your review."
    cm_notify "Consilium: decision.md ready (one arbiter)" "$REL_CASE - $(cm_label "$A1") did not take part"
    exit 0
  fi
  R="$(fail_reason "$A2")"
  echo "$(cm_label "$A2") failed too: $R" >&2
fi

echo "consilium: no arbiter produced a valid draft; decision.md was not synthesized. Logs: $REL_CASE/.logs/decision-*.log" >&2
cm_notify "Consilium: decision synthesis failed" "$REL_CASE - no arbiter answered"
exit 1

#!/usr/bin/env bash
# Decision synthesis mechanics with stub arbiters: joint draft, fallback when either
# arbiter fails or is unavailable, protection of the live file, bounded timeouts.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
clean_env

P="$(new_project)"
ADAPTERS="$(mktemp -d)"
for pair in "stuba:StubA:a-1:STUBA_MODE" "stubb:StubB:b-1:STUBB_MODE"; do
  IFS=: read -r name label model var <<<"$pair"
  cat > "$ADAPTERS/$name.sh" <<STUB
adapter_label() { echo "$label"; }
adapter_models() { echo "$model"; }
adapter_command() { CM_CMD=(bash "\$CM_SKILL_DIR/scripts/mock-agent.sh" "\${$var:-success}"); }
STUB
done
cat > "$ADAPTERS/stubgone.sh" <<'STUB'
adapter_label() { echo "StubGone"; }
adapter_check() { echo "CLI not installed"; return 1; }
adapter_command() { CM_CMD=(false); }
STUB

export CM_ADAPTERS_DIR="$ADAPTERS" CM_HOST=tester CM_LANG=en CM_DECISION_TIMEOUT=5
CASE="$P/consilium/case"
mkdir -p "$CASE/.runners"
: > "$CASE/.runners/expected"
printf '# Brief\n\nquestion\n' > "$CASE/brief.md"
printf '# Tester review (t-1): x\n\n## Verdict\nreal content\n' > "$CASE/tester-review.md"
PLACEHOLDER='> _Not filled in yet. test placeholder._'

run() {  # run <log-name> ; env for modes comes from the caller
  printf '%s\n' "$PLACEHOLDER" > "$CASE/decision.md"
  (cd "$P" && "$BASH_BIN" "$S/write-decision.sh" "$CASE") > "$P/$1.log" 2>&1
}
no_leftovers() { ls "$CASE"/.decision-candidate.* >/dev/null 2>&1 && fail "candidate left behind ($1)"; return 0; }

# 1. Both arbiters succeed -> joint draft, no missing-arbiter note.
CM_ARBITERS="stuba stubb" run both
assert_contains "$CASE/decision.md" "synthesized jointly by StubA (a-1) + StubB (b-1)"
assert_not_contains "$CASE/decision.md" "did not take part"
no_leftovers both

# 2. First arbiter deletes the live file and dies -> live file restored, second writes alone.
STUBA_MODE=delete CM_ARBITERS="stuba stubb" run a-delete
assert_contains "$CASE/decision.md" "synthesized automatically by StubB (b-1)"
assert_contains "$CASE/decision.md" "_Incomplete panel: an arbiter did not take part in the synthesis (StubA"
assert_contains "$P/a-delete.log" "restoring it"
no_leftovers a-delete

# 3. Second arbiter fails -> first draft kept, note names the second.
STUBB_MODE=fail CM_ARBITERS="stuba stubb" run b-fail
assert_contains "$CASE/decision.md" "synthesized automatically by StubA (a-1)"
assert_contains "$CASE/decision.md" "(StubB"
no_leftovers b-fail

# 4. First arbiter is not even installed -> second writes alone, note says unavailable.
CM_ARBITERS="stubgone stubb" run a-gone
assert_contains "$CASE/decision.md" "synthesized automatically by StubB (b-1)"
assert_contains "$CASE/decision.md" "StubGone: unavailable (CLI not installed)"

# 4b. Seats go to the first two AVAILABLE arbiters, not the first two names.
CM_ARBITERS="stubgone stuba stubb" run skip-to-available
assert_contains "$CASE/decision.md" "synthesized jointly by StubA (a-1) + StubB (b-1)"
assert_contains "$CASE/decision.md" "StubGone: unavailable"

# 5. A missing reviewer is listed in the panel note, from disk facts.
printf 'ghost\n' > "$CASE/.runners/expected"
CM_ARBITERS="stuba" run missing-reviewer
assert_contains "$CASE/decision.md" "did not respond as reviewers: ghost"
: > "$CASE/.runners/expected"

# 6. Both arbiters out (one hangs past the timeout, one fails): exits non-zero quickly,
#    the live file is untouched.
start="$(date +%s)"
if STUBA_MODE=hang STUBB_MODE=fail CM_DECISION_TIMEOUT=1 CM_ARBITERS="stuba stubb" run both-fail; then
  fail "must exit non-zero when no arbiter produced a draft"
fi
[ $(( $(date +%s) - start )) -lt 10 ] || fail "timeout did not bound the run"
assert_contains "$CASE/decision.md" "test placeholder"
assert_contains "$CASE/.logs/decision-stuba.log" "timed out after 1s"
no_leftovers both-fail

# 7. Re-running the synthesis replaces the panel note instead of stacking a second one.
printf 'ghost\n' > "$CASE/.runners/expected"
CM_ARBITERS="stuba" run rerun-1
cp "$CASE/decision.md" "$P/first.md"
CM_ARBITERS="stuba" bash -c "cd '$P' && '$BASH_BIN' '$S/write-decision.sh' '$CASE'" > /dev/null 2>&1
[ "$(grep -c '^_Incomplete panel' "$CASE/decision.md")" = 1 ] || fail "panel note duplicated on re-run"

finish "decision synthesis: joint draft, fallbacks, live-file protection, timeouts"

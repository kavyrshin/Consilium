#!/usr/bin/env bash
# Whole pipeline on the mock adapter, in both bundled languages: skeleton, launch guard,
# parallel reviewers, watcher, decision synthesis.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

run_lang() {
  local lang="$1" P CASE
  clean_env
  P="$(new_project)"
  export CM_LANG="$lang" CM_HOST=tester CM_REVIEWERS=mock CM_ARBITERS=mock
  CASE="$(cd "$P" && "$BASH_BIN" "$S/init-case.sh" cache-strategy "Cache strategy" 2>/dev/null)"

  [ -d "$CASE" ] || { fail "[$lang] case dir not created"; return; }
  case "$CASE" in *-cache-strategy) ;; *) fail "[$lang] unexpected case name: $CASE" ;; esac
  for f in brief.md decision.md tasks.json tester-review.md mock-review.md; do assert_file "$CASE/$f"; done
  assert_contains "$CASE/../.gitignore" ".logs/"
  assert_contains "$CASE/tasks.json" '"tasks": []'

  # Same slug the same day gets a numeric suffix instead of overwriting.
  local again
  again="$(cd "$P" && "$BASH_BIN" "$S/init-case.sh" cache-strategy 2>/dev/null)"
  case "$again" in *-cache-strategy-2) ;; *) fail "[$lang] second case should get -2, got $again" ;; esac

  # An unfilled brief must not reach the models.
  if (cd "$P" && "$BASH_BIN" "$S/run-reviewers.sh" "$CASE") >/dev/null 2>&1; then
    fail "[$lang] launch guard did not stop a brief with TODO markers"
  fi

  fill_brief "$CASE/brief.md"
  printf '# Tester review (t-1): x\n\n%s\nok\n' "$CM_R1_PROBE" > "$CASE/tester-review.md"
  (cd "$P" && "$BASH_BIN" "$S/run-reviewers.sh" "$CASE") > /dev/null
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do grep -q "watcher done" "$CASE/.watch.log" 2>/dev/null && break; sleep 1; done

  assert_contains "$CASE/.watch.log" "watcher done: decision.md drafted"
  assert_contains "$CASE/decision.md" "MOCK_ARBITER_OUTPUT"
  assert_contains "$CASE/decision.md" "$HEAD_PROBE"
  assert_contains "$CASE/.runners/mock.done" "ok"
  ls "$CASE"/.decision-candidate.* >/dev/null 2>&1 && fail "[$lang] candidate folder left behind"
  return 0
}

CM_R1_PROBE="## Verdict"; HEAD_PROBE="## Agreement"
run_lang en
CM_R1_PROBE="## Вывод"; HEAD_PROBE="## Согласие"
run_lang ru
finish "init -> reviewers -> watcher -> decision (en, ru)"

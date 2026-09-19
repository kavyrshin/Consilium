#!/usr/bin/env bash
# implement.sh and verify.sh on the mock adapter, with a working tree inside and outside
# the project.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
clean_env

P="$(new_project)"
export CM_HOST=tester CM_LANG=en CM_IMPLEMENTERS=mock CM_VERIFIERS=mock
CASE="$P/consilium/case"
mkdir -p "$CASE"
printf '# Brief\n' > "$CASE/brief.md"
printf '> **DRAFT**\n\n## Authorized code changes\nnothing\n' > "$CASE/decision.md"

# Working tree inside the project.
(cd "$P" && "$BASH_BIN" "$S/implement.sh" "$CASE" "$P" impl) > "$P/impl.log" 2>&1 || fail "implement (inside) failed: $(cat "$P/impl.log")"
assert_file "$CASE/impl-report.md"
assert_contains "$CASE/impl-report.md" "## What changed"

(cd "$P" && "$BASH_BIN" "$S/verify.sh" "$CASE" "$P") > "$P/verify.log" 2>&1 || fail "verify failed: $(cat "$P/verify.log")"
assert_file "$CASE/mock-impl-review.md"
assert_contains "$P/verify.log" "mock: accept"

(cd "$P" && "$BASH_BIN" "$S/implement.sh" "$CASE" "$P" fix) > "$P/fix.log" 2>&1 || fail "fix pass failed"
assert_file "$CASE/fix-report.md"

# Working tree outside the project: documents are copied in, the report comes back.
OUT="$(mktemp -d)"
( cd "$OUT" && git init -q . )
rm -f "$CASE/impl-report.md"
(cd "$P" && "$BASH_BIN" "$S/implement.sh" "$CASE" "$OUT" impl) > "$P/impl2.log" 2>&1 || fail "implement (outside) failed: $(cat "$P/impl2.log")"
assert_file "$CASE/impl-report.md"
assert_file "$OUT/.consilium-context/decision.md"

# An implementer that fails still leaves a report explaining it, and the script fails.
rm -f "$CASE/impl-report.md"
if (cd "$P" && CM_MOCK_MODE=fail "$BASH_BIN" "$S/implement.sh" "$CASE" "$P" impl) > /dev/null 2>&1; then
  fail "failed implementer must make the script exit non-zero"
fi
assert_contains "$CASE/impl-report.md" "wrote no report"

# Unknown pass and missing decision are rejected.
(cd "$P" && "$BASH_BIN" "$S/implement.sh" "$CASE" "$P" bogus) >/dev/null 2>&1 && fail "unknown pass accepted"
finish "implement and verify (inside/outside tree, failure report)"

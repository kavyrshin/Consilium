#!/usr/bin/env bash
# Runs the whole test suite: syntax check, shellcheck (when installed), then each test.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
STATUS=0

echo "== syntax"
for f in ../skills/consilium/scripts/*.sh ../skills/consilium/scripts/adapters/*.sh ../skills/consilium/lang/*.sh ../install.sh; do
  bash -n "$f" || { echo "syntax error in $f" >&2; STATUS=1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck"
  shellcheck -x -S warning ../skills/consilium/scripts/*.sh ../skills/consilium/scripts/adapters/*.sh ../install.sh || STATUS=1
else
  echo "== shellcheck skipped (not installed)"
fi

for t in test-*.sh; do
  echo "== $t"
  bash "$t" || STATUS=1
done
exit $STATUS

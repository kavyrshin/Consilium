#!/usr/bin/env bash
# Installer help stays user-facing, and a copied install includes every runtime file.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
clean_env

HELP="$("$BASH_BIN" "$ROOT/install.sh" --help)"
case "$HELP" in
  *"./install.sh --claude --codex"*) ;;
  *) fail "installer help is missing usage examples" ;;
esac
case "$HELP" in
  *"set -euo pipefail"*) fail "installer help leaked shell implementation" ;;
esac

DEST="$(mktemp -d "${TMPDIR:-/tmp}/consilium-install.XXXXXX")"
"$BASH_BIN" "$ROOT/install.sh" --dir "$DEST/skills" >/dev/null
assert_file "$DEST/skills/consilium/SKILL.md"
assert_file "$DEST/skills/consilium/scripts/reader.sh"
assert_file "$DEST/skills/consilium/reader/reader.cjs"

finish "installer help and copied skill contents"

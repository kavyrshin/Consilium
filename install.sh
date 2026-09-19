#!/usr/bin/env bash
# Installs the consilium skill for Claude Code and/or Codex (and any agent that reads
# ~/.agents/skills).
#
#   ./install.sh                     install for every agent whose config dir exists
#   ./install.sh --claude --codex    choose explicitly (creates the skills dir)
#   ./install.sh --agents            ~/.agents/skills (shared by several agents)
#   ./install.sh --dir PATH          any skills directory, e.g. ./.claude/skills
#   ./install.sh --symlink           link instead of copy (edit the repo, see it live)
#   ./install.sh --force             replace an existing installation
#   ./install.sh --uninstall         remove it from the chosen targets
#
# The skill is one folder (skills/consilium): SKILL.md plus scripts. Nothing outside
# that folder is touched.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills/consilium"
NAME=consilium
TARGETS=()
EXPLICIT=0
SYMLINK=0
FORCE=0
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --claude)    TARGETS+=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"); EXPLICIT=1 ;;
    --codex)     TARGETS+=("${CODEX_HOME:-$HOME/.codex}/skills"); EXPLICIT=1 ;;
    --agents)    TARGETS+=("$HOME/.agents/skills"); EXPLICIT=1 ;;
    --dir)       shift; TARGETS+=("${1:?--dir needs a path}"); EXPLICIT=1 ;;
    --symlink)   SYMLINK=1 ;;
    --force)     FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)   sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ "$EXPLICIT" = 0 ]; then
  [ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ] && TARGETS+=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills")
  [ -d "${CODEX_HOME:-$HOME/.codex}" ] && TARGETS+=("${CODEX_HOME:-$HOME/.codex}/skills")
  if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "Neither ~/.claude nor ~/.codex exists. Choose a target: --claude, --codex, --agents or --dir PATH." >&2
    exit 1
  fi
fi

for skills_dir in "${TARGETS[@]}"; do
  dest="$skills_dir/$NAME"
  if [ "$UNINSTALL" = 1 ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then rm -rf "$dest"; echo "removed  $dest"; else echo "absent   $dest"; fi
    continue
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" = 0 ]; then echo "exists   $dest (use --force to replace)" >&2; continue; fi
    rm -rf "$dest"
  fi
  mkdir -p "$skills_dir"
  if [ "$SYMLINK" = 1 ]; then ln -s "$SRC" "$dest"; echo "linked   $dest -> $SRC"
  else cp -R "$SRC" "$dest"; echo "copied   $dest"; fi
done

[ "$UNINSTALL" = 1 ] && exit 0

echo
echo "Requirements check:"
for tool in bash git python3; do
  if command -v "$tool" >/dev/null 2>&1; then echo "  ok       $tool"; else echo "  MISSING  $tool (required)"; fi
done
echo "Agent CLIs found (each becomes an available reviewer/arbiter/verifier):"
for tool in claude codex opencode dsh; do
  if command -v "$tool" >/dev/null 2>&1; then echo "  found    $tool"; else echo "  -        $tool"; fi
done
echo
echo "Next: in your agent, ask for a consilium (Claude Code: /consilium <question>;"
echo "Codex: \$consilium <question>). Preview the panel first with:"
echo "  bash \"<skill dir>/scripts/run-reviewers.sh\" --plan"

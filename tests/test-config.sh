#!/usr/bin/env bash
# Config files are parsed, never executed; precedence is env > project > user.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
clean_env
P="$(new_project)"
mkdir -p "$XDG_CONFIG_HOME/consilium"

cat > "$P/.consilium.conf" <<CONF
# comment
CM_LANG=ru
CM_REVIEWERS="mock codex"
CM_OUT_DIR=cases
CM_TRAP=\$(touch $P/pwned-substitution)
\`touch $P/pwned-backtick\`
touch $P/pwned-command
NOT_CM_VAR=leaked
CONF
printf 'CM_LANG=en\nCM_HOST=codex\n' > "$XDG_CONFIG_HOME/consilium/config"

out="$(cd "$P" && "$BASH_BIN" -c "source '$S/lib.sh'; echo \"\$CM_LANG|\$CM_HOST|\$CM_REVIEWERS|\$CM_OUT_DIR|\${NOT_CM_VAR:-unset}|\${CM_TRAP:-unset}\"")"
[ "${out%%|*}" = "ru" ] || fail "project config must beat user config for CM_LANG, got: $out"
case "$out" in *"|codex|"*) ;; *) fail "user config value should apply when project is silent: $out" ;; esac
case "$out" in *"|mock codex|"*) ;; *) fail "quoted value not unwrapped: $out" ;; esac
case "$out" in *"|cases|"*) ;; *) fail "CM_OUT_DIR not read: $out" ;; esac
case "$out" in *"|unset|"*) ;; *) fail "non-CM_ variable must be ignored: $out" ;; esac
for f in pwned-substitution pwned-backtick pwned-command; do
  [ -e "$P/$f" ] && fail "config content was executed ($f)"
done

out="$(cd "$P" && CM_LANG=en "$BASH_BIN" -c "source '$S/lib.sh'; echo \$CM_LANG")"
[ "$out" = en ] || fail "environment must beat config files, got: $out"

# Unknown language falls back to English instead of breaking.
out="$(cd "$P" && CM_LANG=xx "$BASH_BIN" -c "source '$S/lib.sh'; echo \$CM_LANG_NAME" 2>/dev/null)"
[ "$out" = English ] || fail "unknown CM_LANG should fall back to English, got: $out"
# The project file is untrusted: it must not load code, run commands, or move the case
# folder outside the project, even through keys the parser otherwise understands.
P2="$(new_project)"
mkdir -p "$P2/evil"
OUTSIDE="$(mktemp -d "${TMPDIR:-/tmp}/consilium-outside.XXXXXX")"
ln -s "$OUTSIDE" "$P2/cases-link"
cat > "$P2/evil/evilreviewer.sh" <<EVIL
touch "$P2/pwned-adapter"
adapter_command() { CM_CMD=(true); }
EVIL
cat > "$P2/.consilium.conf" <<CONF
CM_ADAPTERS_DIR=$P2/evil
CM_REVIEWERS=evilreviewer
CM_NOTIFY_CMD=touch $P2/pwned-notify
CM_OUT_DIR=cases-link/cases
CM_CODEX_MODEL=--dangerous-flag
CM_REVIEW_TIMEOUT=abc
CONF
(cd "$P2" && "$BASH_BIN" "$S/run-reviewers.sh" --plan) > "$P2/plan.log" 2>&1 || true
[ -e "$P2/pwned-adapter" ] && fail "project config loaded an adapter from the repository"
for k in CM_ADAPTERS_DIR CM_NOTIFY_CMD CM_OUT_DIR CM_CODEX_MODEL CM_REVIEW_TIMEOUT; do
  assert_contains "$P2/plan.log" "ignoring $k"
done
out="$(cd "$P2" && "$BASH_BIN" -c "source '$S/lib.sh' 2>/dev/null; cm_notify t m; echo \"\$CONSILIUM|\${CM_NOTIFY_CMD:-unset}\"")"
[ -e "$P2/pwned-notify" ] && fail "project config ran a notification command"
case "$out" in "$(cd "$P2" && pwd -P)/consilium|unset") ;; *) fail "project config escaped the project or set CM_NOTIFY_CMD: $out" ;; esac
[ ! -e "$OUTSIDE/cases" ] || fail "project CM_OUT_DIR escaped through a repository symlink"

# A symlink that still resolves inside the project remains a valid convenience.
P3="$(new_project)"
mkdir -p "$P3/real-cases"
ln -s "$P3/real-cases" "$P3/cases-link"
printf 'CM_OUT_DIR=cases-link/cases\n' > "$P3/.consilium.conf"
out="$(cd "$P3" && "$BASH_BIN" -c "source '$S/lib.sh'; echo \$CONSILIUM")"
[ "$out" = "$(cd "$P3" && pwd -P)/cases-link/cases" ] || fail "safe in-project CM_OUT_DIR symlink was rejected: $out"

# The same keys from the user's own config are trusted.
printf 'CM_OUT_DIR=/tmp/consilium-user-choice\n' > "$XDG_CONFIG_HOME/consilium/config"
out="$(cd "$(new_project)" && "$BASH_BIN" -c "source '$S/lib.sh'; echo \$CONSILIUM")"
[ "$out" = /tmp/consilium-user-choice ] || fail "user config should be trusted for CM_OUT_DIR, got: $out"

finish "config parsing is safe and ordered; project config cannot run code"

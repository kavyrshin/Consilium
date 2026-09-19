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
finish "config parsing is safe and ordered"

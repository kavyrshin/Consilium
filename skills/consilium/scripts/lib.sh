#!/usr/bin/env bash
# Shared helpers for every consilium script. Meant to be sourced, does nothing on
# its own. Stays compatible with bash 3.2 (the stock macOS /bin/bash): no
# associative arrays, no `${var,,}`, no `mapfile`.
#
# Settings precedence (highest first): environment > <project>/.consilium.conf >
# ~/.config/consilium/config > built-in defaults. Config files are parsed as plain
# KEY=VALUE lines, never sourced.
#
# The project file is UNTRUSTED: it arrives with whatever repository was cloned. It may
# only set an allowlist of keys, each with a validated value (cm_project_key_ok), so it
# cannot point the skill at code to load (CM_ADAPTERS_DIR), a command to run
# (CM_NOTIFY_CMD) or a folder outside the project. Everything else is honoured only from
# the environment, CM_CONFIG or the user's own config file.

CM_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------- configuration

# Allowlist for the untrusted project file: key plus a conservative value check.
cm_project_key_ok() {
  local key="$1" val="$2" word
  case "$key" in
    CM_LANG|CM_HOST)
      case "$val" in ''|*[!a-z0-9_-]*) return 1 ;; esac ;;
    CM_REVIEWERS|CM_ARBITERS|CM_VERIFIERS|CM_IMPLEMENTERS|CM_SKIP_REVIEWERS|CM_SKIP_VERIFIERS)
      case "$val" in *[!a-z0-9_\ -]*) return 1 ;; esac ;;
    CM_OUT_DIR)
      case "$val" in ''|/*|*[!A-Za-z0-9._/-]*) return 1 ;; esac
      case "/$val/" in */../*|*/./*) return 1 ;; esac ;;
    CM_REVIEW_TIMEOUT|CM_DECISION_TIMEOUT|CM_VERIFY_TIMEOUT|CM_IMPLEMENT_TIMEOUT)
      case "$val" in ''|*[!0-9]*) return 1 ;; esac ;;
    CM_CODEX_MODEL|CM_CLAUDE_MODEL|CM_CLAUDE_EFFORT|CM_OPENCODE_MODEL|CM_OPENCODE_MODELS|CM_DEEPSEEK_MODEL)
      case "$val" in *[!A-Za-z0-9._/:~@\ -]*) return 1 ;; esac
      # A value that starts with "-" could be taken for a CLI option.
      for word in $val; do case "$word" in -*) return 1 ;; esac; done ;;
    CM_DISABLE_NOTIFICATIONS)
      case "$val" in 0|1) ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

# The lexical CM_OUT_DIR check above rejects explicit traversal. Resolve existing
# symlinks as well, so a relative path supplied by an untrusted repository cannot
# leave the physical project root. Nonexistent trailing components are handled by
# realpath and may be created later by init-case.sh.
cm_project_out_dir_ok() {
  python3 - "$CM_PROJECT" "$1" <<'PYEOF'
import os
import sys

root = os.path.realpath(sys.argv[1])
candidate = os.path.realpath(os.path.join(root, sys.argv[2]))
try:
    inside = os.path.commonpath((root, candidate)) == root
except ValueError:
    inside = False
sys.exit(0 if inside else 1)
PYEOF
}

# cm_read_conf <file> [untrusted]
cm_read_conf() {
  local file="$1" untrusted="${2:-}" line key val
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in CM_[A-Z0-9_]*=*) ;; *) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in *[!A-Z0-9_]*) continue ;; esac
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    if [ -n "$untrusted" ] && ! cm_project_key_ok "$key" "$val"; then
      echo "consilium: ignoring $key from $file (not allowed in a project config, or invalid value)" >&2
      continue
    fi
    if [ -n "$untrusted" ] && [ "$key" = CM_OUT_DIR ] && ! cm_project_out_dir_ok "$val"; then
      echo "consilium: ignoring $key from $file (path resolves outside the project)" >&2
      continue
    fi
    # Anything already set (environment or a higher-priority file) wins.
    if [ -z "${!key+x}" ]; then export "$key=$val"; fi
  done < "$file"
}

CM_PROJECT="${CM_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# Physical path: on macOS /var is a symlink to /private/var, and git reports the physical
# one. Comparing a logical and a physical spelling of the same directory would wrongly
# treat a working tree inside the project as being outside it.
CM_PROJECT="$(cd "$CM_PROJECT" && pwd -P)"
[ -n "${CM_CONFIG:-}" ] && cm_read_conf "$CM_CONFIG"
cm_read_conf "$CM_PROJECT/.consilium.conf" untrusted
cm_read_conf "${XDG_CONFIG_HOME:-$HOME/.config}/consilium/config"

# Where cases live, relative to the project root (an absolute path also works, but
# the sandboxed reviewers can only write inside the project, so keep it inside).
: "${CM_OUT_DIR:=consilium}"
: "${CM_LANG:=en}"
# Which agent is running the skill. It writes its own review by hand, so it is never
# also launched as an external reviewer.
: "${CM_HOST:=claude}"
# Space-separated adapter names. Unavailable ones (CLI missing, no model configured)
# are skipped automatically and reported.
: "${CM_REVIEWERS:=claude codex opencode deepseek}"
: "${CM_ARBITERS:=codex claude}"
: "${CM_VERIFIERS:=codex claude}"
: "${CM_IMPLEMENTERS:=claude codex opencode}"
: "${CM_REVIEW_TIMEOUT:=1800}"
: "${CM_DECISION_TIMEOUT:=900}"
: "${CM_VERIFY_TIMEOUT:=2700}"
: "${CM_IMPLEMENT_TIMEOUT:=2700}"

case "$CM_OUT_DIR" in
  /*) CONSILIUM="${CM_OUT_DIR%/}" ;;
  *)  CONSILIUM="$CM_PROJECT/${CM_OUT_DIR%/}" ;;
esac

# The host name becomes part of a file name (<host>-review.md).
case "$CM_HOST" in ''|*[!a-z0-9_-]*) echo "consilium: invalid CM_HOST='$CM_HOST', using claude" >&2; CM_HOST=claude ;; esac
case "$CM_LANG" in *[!a-z-]*|'') CM_LANG=en ;; esac
if [ -f "$CM_SKILL_DIR/lang/$CM_LANG.sh" ]; then
  # shellcheck source=/dev/null
  . "$CM_SKILL_DIR/lang/$CM_LANG.sh"
else
  echo "consilium: unknown CM_LANG='$CM_LANG', falling back to en" >&2
  CM_LANG=en
  # shellcheck source=/dev/null
  . "$CM_SKILL_DIR/lang/en.sh"
fi

cm_rel() { echo "${1#"$CM_PROJECT"/}"; }

# Current branch of a working tree; works before the first commit and on a detached HEAD.
cm_branch() {
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null ||
    git -C "$1" rev-parse --short HEAD 2>/dev/null ||
    echo "?"
}

# ---------------------------------------------------------------------- adapters
# An adapter is a small file adapters/<name>.sh that teaches the framework how to
# call one agent CLI. It may define (all optional except adapter_command):
#   adapter_label            display name, e.g. "Codex"
#   adapter_models           space-separated model chain; first one that produces the
#                            expected file wins. "default" = let the CLI choose.
#   adapter_check            exit 0 when usable; otherwise print the reason, exit 1
#   adapter_attempts         attempts per model (default 1)
#   adapter_command <prompt> fill the array CM_CMD with the command to run; the
#                            framework runs it from the project root under a timeout
#   adapter_failure_reason <log>
#   ADAPTER_STDOUT_FALLBACK=1  if the agent answered on stdout instead of writing the
#                            file, save stdout as the review
# Adapters are looked up in $CM_ADAPTERS_DIR, ~/.config/consilium/adapters, then the
# bundled scripts/adapters/.

cm_adapter_file() {
  local name="$1" dir
  case "$name" in ''|*[!a-z0-9_-]*) return 1 ;; esac
  for dir in "${CM_ADAPTERS_DIR:-}" "${XDG_CONFIG_HOME:-$HOME/.config}/consilium/adapters" "$CM_SKILL_DIR/scripts/adapters"; do
    [ -n "$dir" ] && [ -f "$dir/$name.sh" ] && { echo "$dir/$name.sh"; return 0; }
  done
  return 1
}

# Must run inside a subshell: it (re)defines the adapter_* functions.
cm_adapter_load() {
  local name="$1" file
  file="$(cm_adapter_file "$name")" || return 1
  ADAPTER_NAME="$name"
  ADAPTER_STDOUT_FALLBACK=0
  adapter_label() { echo "$ADAPTER_NAME"; }
  adapter_models() { echo default; }
  adapter_check() { return 0; }
  adapter_attempts() { echo 1; }
  adapter_failure_reason() {
    grep -m1 -iE "usage limit|rate limit|quota|unauthorized|forbidden|not available" "$1" 2>/dev/null | head -c 160
  }
  # shellcheck source=/dev/null
  . "$file"
}

cm_label() {
  local out
  out="$( (cm_adapter_load "$1" && adapter_label) 2>/dev/null)" || out=""
  echo "${out:-$1}"
}
cm_models() { ( cm_adapter_load "$1" && adapter_models ) 2>/dev/null; }
cm_first_model() { local m; m="$(cm_models "$1")"; echo "${m%% *}"; }
cm_attempts() { ( cm_adapter_load "$1" && adapter_attempts ) 2>/dev/null || echo 1; }
cm_stdout_fallback() { ( cm_adapter_load "$1" && echo "$ADAPTER_STDOUT_FALLBACK" ) 2>/dev/null || echo 0; }
cm_failure_reason() { ( cm_adapter_load "$1" && adapter_failure_reason "$2" ) 2>/dev/null; }

# Prints the reason and returns 1 when the adapter is not usable.
cm_check() {
  if ! cm_adapter_file "$1" >/dev/null; then echo "unknown adapter"; return 1; fi
  ( cm_adapter_load "$1" && adapter_check )
}

# cm_available <names...>: prints usable adapters one per line; reasons for the
# rest go to stderr.
cm_available() {
  local name reason
  for name in "$@"; do
    if reason="$(cm_check "$name")"; then
      echo "$name"
    else
      echo "consilium: '$name' unavailable: ${reason:-no reason given}" >&2
    fi
  done
}

# Runs one agent call, walking the model chain x attempts until check_fn passes.
#   cm_invoke <adapter> <cwd> <timeout> <log> <prompt_fn> <check_fn>
# prompt_fn <label> <model> must set CM_PROMPT (and may set other globals).
# Afterwards CM_USED_MODEL is the model of the last call and CM_LAST_STATUS its exit code.
cm_invoke() {
  local adapter="$1" cwd="$2" timeout="$3" log="$4" prompt_fn="$5" check_fn="$6"
  local label models attempts model attempt
  label="$(cm_label "$adapter")"
  models="$(cm_models "$adapter")"
  # A chain is for reviewers, where a failed model leaves nothing behind. An implementer
  # that failed halfway may have edited files, so it must not fall through to another model.
  if [ -n "${CM_ONLY_FIRST_MODEL:-}" ]; then models="${models%% *}"; fi
  attempts="${CM_ATTEMPTS:-$(cm_attempts "$adapter")}"
  mkdir -p "$(dirname "$log")"
  for model in $models; do
    attempt=1
    while [ "$attempt" -le "$attempts" ]; do
      if [ "$attempt" -gt 1 ]; then
        echo "--- retry $attempt/$attempts for $model in ${CM_RETRY_DELAY:-20}s" >> "$log"
        sleep "${CM_RETRY_DELAY:-20}"
      fi
      CM_PROMPT=""
      # Documents name the model that wrote them. "default" means the CLI picked it from
      # its own settings, which we cannot see, so say exactly that.
      CM_USED_MODEL="$model"
      [ "$model" = default ] && CM_USED_MODEL="CLI default model"
      "$prompt_fn" "$label" "$CM_USED_MODEL"
      CM_LAST_STATUS=0
      echo "=== $(date '+%F %T') $adapter model=$model attempt=$attempt/$attempts" >> "$log"
      (
        cm_adapter_load "$adapter" &&
        CM_MODEL="$model" &&
        adapter_command "$CM_PROMPT" &&
        cd "$cwd" &&
        run_with_timeout "$timeout" "${CM_CMD[@]}"
      ) >> "$log" 2>&1 || CM_LAST_STATUS=$?
      if "$check_fn"; then return 0; fi
      attempt=$((attempt + 1))
    done
  done
  return 1
}

# -------------------------------------------------------------------- utilities

# Stock macOS has no timeout(1). Runs the command in its own process group so that on
# a deadline the CLI and any children it spawned are all terminated. Exit 124 = timeout.
run_with_timeout() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" <<'PYEOF'
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
process = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    status = process.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print(f"ERROR: {os.path.basename(sys.argv[2])} timed out after {seconds}s", file=sys.stderr)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    status = 124
sys.exit(status)
PYEOF
}

# A file counts as written when it exists, is non-empty and no longer starts with the
# skeleton placeholder. The placeholder is matched as a whole line in either bundled
# language, not as a phrase anywhere in the text: a review that quotes the phrase while
# discussing the readiness check itself must not be rejected as unfilled.
cm_written() {
  [ -s "$1" ] && ! grep -Eq '^> _(Not filled in|Не заполнено)' "$1" 2>/dev/null
}

# Runners leave a marker so the watcher does not have to wait out its timeout for a
# reviewer that already failed.
cm_mark_done() {
  mkdir -p "$1/.runners"
  printf '%s\n' "$3" > "$1/.runners/$2.done"
}

# Empty argument -> newest case; a directory -> as is; otherwise substring match.
cm_resolve_case() {
  local arg="${1:-}"
  if [ -z "$arg" ]; then
    ls -d "$CONSILIUM"/*/ 2>/dev/null | sort | tail -1
    return
  fi
  if [ -d "$arg" ]; then echo "$arg"; return; fi
  if [ -d "$CONSILIUM/$arg" ]; then echo "$CONSILIUM/$arg"; return; fi
  ls -d "$CONSILIUM"/*"$arg"*/ 2>/dev/null | sort | tail -1
}

# Sets CASE_DIR / REL_CASE or exits. Optional second argument: file that must exist.
cm_need_case() {
  CASE_DIR="$(cm_resolve_case "${1:-}")"
  CASE_DIR="${CASE_DIR%/}"
  local need="${2:-brief.md}"
  if [ -z "$CASE_DIR" ] || [ ! -f "$CASE_DIR/$need" ]; then
    echo "consilium: no case with $need found (argument: '${1:-<empty>}', looked in $CONSILIUM)" >&2
    exit 1
  fi
  CASE_DIR="$(cd "$CASE_DIR" && pwd -P)"
  REL_CASE="$(cm_rel "$CASE_DIR")"
}

# Desktop notification, best effort. CM_NOTIFY_CMD (given title and message as $1 $2)
# overrides everything; CM_DISABLE_NOTIFICATIONS=1 silences it.
cm_notify() {
  local title="$1" message="$2"
  [ "${CM_DISABLE_NOTIFICATIONS:-0}" = "1" ] && return 0
  if [ -n "${CM_NOTIFY_CMD:-}" ]; then
    $CM_NOTIFY_CMD "$title" "$message" >/dev/null 2>&1 || true
  elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$message" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" >/dev/null 2>&1 || true
  fi
}

# cm_render <template> KEY=VALUE...   replaces {{KEY}} in the template, prints result.
cm_render() {
  python3 - "$@" <<'PYEOF'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
for pair in sys.argv[2:]:
    key, _, value = pair.partition("=")
    text = text.replace("{{" + key + "}}", value)
sys.stdout.write(text)
PYEOF
}

# Names of the external reviewers that would run: configured, minus the host (who
# writes by hand) and minus CM_SKIP_REVIEWERS, minus unavailable ones (reported on
# stderr).
cm_plan_reviewers() {
  local name skip=" ${CM_SKIP_REVIEWERS:-} " wanted=""
  for name in $CM_REVIEWERS; do
    [ "$name" = "$CM_HOST" ] && continue
    case "$skip" in *" $name "*) continue ;; esac
    wanted="$wanted $name"
  done
  # shellcheck disable=SC2086
  cm_available $wanted
}

# Shared wording of the reviewer prompt. Kept in English on purpose: the prompt is
# machine-to-machine, and only the brief's own language decides the review's language.
cm_prompt_review() {
  local rel_case="$1" review_file="$2" label="$3" model="$4"
  echo "Read ${rel_case}/brief.md in this project and write an independent review to ${rel_case}/${review_file}. Start the file with a level-1 heading in exactly this form: '# ${label} ${CM_L_REVIEW_WORD} (${model}): <short topic title from the brief>' - use the model label given here verbatim, do not guess which model you are. Then match exactly the section headings and structure given in the response-format section near the end of that brief (six required headings, in the same language as the brief; copy them verbatim, do not translate). Other reviewers work on the same brief in parallel and write their own *-review.md files in that same folder. Independence is the point of this exercise: do not open or read any other *-review.md file until after you have finished writing and saving your own review file. Do not modify anything except ${rel_case}/${review_file}."
}

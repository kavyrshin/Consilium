# Adapter: OpenAI Codex CLI (`codex exec`, non-interactive).
#
# The model and reasoning effort come from ~/.codex/config.toml unless CM_CODEX_MODEL
# is set: one source of truth, no second copy to keep in sync.
# Sandbox workspace-write lets the agent write its file into the case folder but not
# touch anything outside the project.

adapter_label() { echo "Codex"; }

adapter_models() {
  local m="${CM_CODEX_MODEL:-}"
  if [ -z "$m" ]; then
    m="$(awk -F'"' '/^model *=/ {print $2; exit}' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null)"
  fi
  echo "${m:-default}"
}

adapter_check() {
  if ! command -v codex >/dev/null 2>&1; then echo "codex CLI not found in PATH"; return 1; fi
}

adapter_command() {
  CM_CMD=(codex exec --sandbox workspace-write --skip-git-repo-check)
  if [ "$CM_MODEL" != default ]; then CM_CMD+=(--model "$CM_MODEL"); fi
  CM_CMD+=("$1")
}

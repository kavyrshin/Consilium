# Adapter: DeepSeek Harness (`dsh --profile headless`). Optional, off unless found.
#
# The model and effort are read from ~/.dsh/settings.yaml (the headless profile has no
# flags for them). If your harness differs, copy this file to
# ~/.config/consilium/adapters/ and adjust adapter_command.

ADAPTER_STDOUT_FALLBACK=1

# dsh is often run through npx and not on PATH; look in PATH first, then the npx cache.
_dsh_bin() {
  if command -v dsh >/dev/null 2>&1; then echo "dsh"; return; fi
  ls -t "$HOME"/.npm/_npx/*/node_modules/.bin/dsh 2>/dev/null | head -1
}

adapter_label() { echo "DeepSeek Harness"; }

adapter_models() {
  local m="${CM_DEEPSEEK_MODEL:-}"
  if [ -z "$m" ]; then
    m="$(awk '/^agent-default-model:/{f=1;next} f&&/^  model:/{print $2;exit} f&&/^[^ ]/{exit}' "$HOME/.dsh/settings.yaml" 2>/dev/null)"
  fi
  echo "${m:-default}"
}

adapter_check() {
  if [ -z "$(_dsh_bin)" ]; then echo "dsh not found (PATH or npx cache)"; return 1; fi
}

adapter_command() {
  CM_CMD=("$(_dsh_bin)" --profile headless "$1")
}

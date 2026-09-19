# Adapter: Open Code (opencode.ai, `opencode run`).
#
# Install: npm install -g opencode-ai
#
# opencode has no default model in headless mode. Without an explicit --model the CLI
# fails with an opaque "Unexpected server error" that hides a ProviderNoProvidersError,
# so a model MUST be configured; this adapter reports itself unavailable until it is:
#
#   CM_OPENCODE_MODEL=provider/model            one model
#   CM_OPENCODE_MODELS="prov/a prov/b prov/c"   a fallback chain, tried in order
#
# List what you can use with `opencode models`. Free endpoints come and go, which is
# why each model gets two attempts (a transient "not available in your country" has
# been seen to succeed a minute later) before the chain moves on.

adapter_label() { echo "Open Code"; }
adapter_models() { echo "${CM_OPENCODE_MODELS:-${CM_OPENCODE_MODEL:-}}"; }
adapter_attempts() { echo 2; }

adapter_check() {
  if ! command -v opencode >/dev/null 2>&1; then echo "opencode CLI not found in PATH"; return 1; fi
  if [ -z "$(adapter_models)" ]; then
    echo "no model configured: set CM_OPENCODE_MODEL (see 'opencode models')"
    return 1
  fi
}

adapter_command() {
  CM_CMD=(opencode run --model "$CM_MODEL" "$1")
}

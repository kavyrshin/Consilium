# Adapter: Claude Code in headless mode (`claude -p`).
#
# Useful as an external reviewer/arbiter when the host agent is something else (for
# example Codex), or as an extra independent voice next to the host.
# Reviewers and arbiters may only read files and write; verifiers and implementers
# may also run shell commands (they have to run checks / build). Everything else is
# denied because headless mode cannot ask for permission.
#
# CM_CLAUDE_MODEL   model alias or id passed to --model (default: the CLI's own)
# CM_CLAUDE_EFFORT  passed to --effort when set

ADAPTER_STDOUT_FALLBACK=1

adapter_label() { echo "Claude Code"; }
adapter_models() { echo "${CM_CLAUDE_MODEL:-default}"; }

adapter_check() {
  if ! command -v claude >/dev/null 2>&1; then echo "claude CLI not found in PATH"; return 1; fi
}

adapter_command() {
  local tools="Read,Write,Edit,Glob,Grep"
  case "${CM_ROLE:-reviewer}" in verifier|implementer) tools="$tools,Bash" ;; esac
  CM_CMD=(claude -p "$1" --permission-mode acceptEdits --allowedTools "$tools")
  if [ "$CM_MODEL" != default ]; then CM_CMD+=(--model "$CM_MODEL"); fi
  if [ -n "${CM_CLAUDE_EFFORT:-}" ]; then CM_CMD+=(--effort "$CM_CLAUDE_EFFORT"); fi
}

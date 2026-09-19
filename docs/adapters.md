# Writing an adapter

An adapter teaches the framework how to call one agent CLI. It is a shell file named `<name>.sh`. The framework looks for it in, in order:

1. `$CM_ADAPTERS_DIR`
2. `~/.config/consilium/adapters/`
3. the bundled `skills/consilium/scripts/adapters/`

Names are lowercase letters, digits, `-` and `_`. Then use the name in `CM_REVIEWERS`, `CM_ARBITERS`, `CM_VERIFIERS` or `CM_IMPLEMENTERS`.

## The contract

Only `adapter_command` is required. Every role (reviewer, arbiter, verifier, implementer) works the same way: the framework hands the agent a prompt that names a file to write, runs the command from the project root under a timeout, and then judges the result **by the file's content, not by the exit code**. Exit codes of agent CLIs are unreliable.

| Function / variable | Purpose | Default |
| --- | --- | --- |
| `adapter_command <prompt>` | set the array `CM_CMD` to the command line to run | required |
| `adapter_label` | display name used in headings and notes | the adapter name |
| `adapter_models` | space-separated model chain; the first one that produces the file wins. `default` means "let the CLI choose" | `default` |
| `adapter_check` | exit 0 if usable; otherwise print the reason and exit 1 | always usable |
| `adapter_attempts` | attempts per model | `1` |
| `adapter_failure_reason <log>` | one line explaining a failure, shown to the user | greps for quota / rate-limit / auth wording |
| `ADAPTER_STDOUT_FALLBACK=1` | if the agent answers on stdout instead of writing the file, save stdout as the review | `0` |

Available inside `adapter_command`: `CM_MODEL` (the model being tried), `CM_ROLE` (`reviewer`, `arbiter`, `verifier` or `implementer`), `CM_SKILL_DIR`. The model is always passed by you explicitly when the CLI needs it; a label of `default` means do not pass one.

## Example

The CLI name and flags below are illustrative; use your CLI's real non-interactive options.

```bash
# ~/.config/consilium/adapters/gemini.sh
adapter_label() { echo "Gemini"; }
adapter_models() { echo "${CM_GEMINI_MODEL:-default}"; }

adapter_check() {
  command -v gemini >/dev/null 2>&1 || { echo "gemini CLI not found in PATH"; return 1; }
}

adapter_command() {
  CM_CMD=(gemini --yolo)
  [ "$CM_MODEL" != default ] && CM_CMD+=(--model "$CM_MODEL")
  CM_CMD+=(--prompt "$1")
}
```

Check it without spending anything:

```bash
CM_REVIEWERS="gemini" bash ~/.claude/skills/consilium/scripts/run-reviewers.sh --plan
```

## Things worth getting right

- **Write access.** The agent has to be able to create the review file. For sandboxed CLIs use a mode that allows writing inside the project but not outside it (Codex: `--sandbox workspace-write`).
- **Verifiers and implementers run commands** (tests, syntax checks). Give `CM_ROLE=verifier|implementer` shell access and reviewers/arbiters none, as the bundled `claude` adapter does.
- **Headless means no prompts.** An agent that stops to ask for permission will hang until the timeout. Allow exactly what the role needs.
- **Models that need a flag.** Some CLIs (Open Code) have no default model headless and fail with an opaque error; report that from `adapter_check` so the adapter is skipped with a clear reason.

## Testing without a model

The `mock` adapter writes a well-formed placeholder review, decision, verification or report, and `scripts/mock-agent.sh` has failure modes (`fail`, `hang`, `delete`, `stdout`). The test suite builds stub adapters on it; see `tests/test-decision.sh`.

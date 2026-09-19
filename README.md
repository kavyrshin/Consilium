# Consilium

[![tests](https://github.com/kavyrshin/Consilium/actions/workflows/ci.yml/badge.svg)](https://github.com/kavyrshin/Consilium/actions/workflows/ci.yml) [![release](https://img.shields.io/github/v/release/kavyrshin/Consilium)](https://github.com/kavyrshin/Consilium/releases/latest) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Русская версия](README.ru.md)

A skill for **Claude Code** and **Codex** that runs a *consilium*: several independent models review the same technical question, two arbiters merge the reviews into a **draft** decision, and only after you confirm it does an implementer make the changes and verifiers check them. The human is always the final arbiter; no model decides.

One folder, one `SKILL.md`, plain bash scripts. Everything the process produces is ordinary markdown in your project, so it is reviewable, diffable and yours to keep.

```
brief.md ─┬─► host review (the agent you are talking to)  ┐
          ├─► reviewer 2 (external CLI, in parallel)      ├─► decision.md  ─► you confirm
          └─► reviewer 3 (external CLI, in parallel)      ┘   (DRAFT, two arbiters)
                                                                   │  only after confirmation
                                   implementer ─► verifiers ─► implementer fixes ─► you review the diff
```

## Why

One model reviewing its own idea tends to agree with itself. Independent reviews from different models find different things, and forcing each to write down facts, assumptions, risks and a recommendation before reading the others keeps them honest. The arbiters must state disagreements explicitly instead of averaging them away, and the script (not a model) records who did not answer.

## Requirements

- `bash` 3.2+ (stock macOS works), `git`, `python3`; Node.js 18+ only for the optional reader
- At least one agent CLI on your `PATH`. Each one you have becomes a usable reviewer, arbiter, verifier or implementer:

| Adapter | CLI | Notes |
| --- | --- | --- |
| `claude` | [Claude Code](https://claude.com/claude-code) (`claude -p`) | |
| `codex` | [Codex CLI](https://github.com/openai/codex) (`codex exec`) | model comes from `~/.codex/config.toml` |
| `opencode` | [Open Code](https://opencode.ai) (`opencode run`) | needs `CM_OPENCODE_MODEL`, see below |
| `deepseek` | DeepSeek Harness (`dsh`) | optional, off unless found |
| `mock` | none | writes placeholder text; to try the pipeline without any model |

More: [write your own adapter](docs/adapters.md), it is a ~10 line file.

The **host** is whichever agent you run the skill in. It writes its own review by hand, so it is never launched a second time. With only one CLI installed the consilium still runs, with a smaller panel, and the decision says so.

## Install

Stable release (recommended):

```bash
git clone --branch v0.1.0 --depth 1 https://github.com/kavyrshin/Consilium.git
cd Consilium
./install.sh                # every agent whose config dir exists (~/.claude, ~/.codex)
```

Latest development version:

```bash
git clone https://github.com/kavyrshin/Consilium.git
cd Consilium
./install.sh                # every agent whose config dir exists (~/.claude, ~/.codex)
```

Options: `--claude`, `--codex`, `--agents` (`~/.agents/skills`), `--dir PATH` (e.g. `./.claude/skills` for one project), `--symlink` (edit the repo, see changes live), `--force`, `--uninstall`.

Or copy `skills/consilium/` into your agent's skills directory by hand.

## Use

In your agent:

| Agent | Invoke |
| --- | --- |
| Claude Code | `/consilium Should we cache X in Redis or in-process?` |
| Codex | `$consilium Should we cache X in Redis or in-process?` |

The skill is set to run **only when you ask for it**: it spends model quota and sends project files to several providers.

What happens:

1. The agent shows the panel (`run-reviewers.sh --plan`) and creates `consilium/<date>-<slug>/`.
2. It researches facts (read-only) and fills in `brief.md`. Reviewers get nothing until the brief is complete.
3. External reviewers start in parallel, in the background. The agent writes its own review without reading theirs.
4. A watcher drafts `decision.md` when everyone has answered or failed. Two arbiters: the first drafts, the second revises and must record disagreement.
5. **You read and confirm the draft.** Nothing is implemented before that (unless you said so up front).
6. An implementer applies only what "Authorized code changes" lists, in a separate git worktree; verifiers check it independently; the implementer fixes what they found. No commits, no pushes.

See [`examples/`](examples/) for what a case folder looks like.

## Configure

Plain `KEY=VALUE`, in `<project>/.consilium.conf` or `~/.config/consilium/config`. Environment variables win over the project file, which wins over the user file. Files are **parsed, never executed**. The project file is treated as untrusted, because it comes with whatever repository you cloned: it may only set the panel, language, models, timeouts and a relative case folder inside the project. Settings that load code or run commands (`CM_ADAPTERS_DIR`, `CM_NOTIFY_CMD`) and paths outside the project are accepted only from the environment or your user config; the skill prints what it ignored. Start from [`consilium.example.conf`](skills/consilium/consilium.example.conf).

| Setting | Default | Meaning |
| --- | --- | --- |
| `CM_LANG` | `en` | language of documents: `en` or `ru` (see below to add more) |
| `CM_HOST` | `claude` | the agent running the skill (`claude` / `codex`) |
| `CM_REVIEWERS` | `claude codex opencode deepseek` | external reviewer adapters; unavailable ones are skipped and reported |
| `CM_ARBITERS` | `codex claude` | the first two available ones in the list synthesize the draft |
| `CM_VERIFIERS` | `codex claude` | verify the implementation, in parallel |
| `CM_IMPLEMENTERS` | `claude codex opencode` | first available implements |
| `CM_OUT_DIR` | `consilium` | case folder, relative to the project root |
| `CM_OPENCODE_MODEL(S)` | unset | **required** to enable Open Code: `opencode` has no default model in headless mode |
| `CM_CODEX_MODEL`, `CM_CLAUDE_MODEL`, `CM_CLAUDE_EFFORT` | CLI's own | model overrides |
| `CM_*_TIMEOUT` | 30 / 15 / 45 / 45 min | review / decision / verify / implement |

Preview who would run and who would be skipped, without starting anything:

```bash
bash ~/.claude/skills/consilium/scripts/run-reviewers.sh --plan   # installed for Claude Code
bash ~/.codex/skills/consilium/scripts/run-reviewers.sh --plan    # installed for Codex
```

### Languages

English is the default, Russian is bundled (`CM_LANG=ru`). To add one, copy `skills/consilium/lang/en.sh` and `skills/consilium/templates/en/` to your code, translate the values, set `CM_LANG=<code>`. Section headings are part of the contract (the decision validator matches them exactly), so change the wording, not the mechanism.

## Reader

A local web page for reading cases: every case in the sidebar, documents in process order (brief, reviews, decision, implementation), updating live while reviewers and arbiters write. Needs Node.js 18+.

```bash
bash ~/.claude/skills/consilium/scripts/reader.sh --open     # http://localhost:4600
```

Run it from the project root (`~/.codex/...` if you installed for Codex). `--port N` changes the port. It listens on `127.0.0.1` only, refuses foreign `Host` headers, serves nothing but the case markdown, and renders documents sanitized under a strict Content-Security-Policy: they are written by models that may have read hostile content.

### Sharing through ngrok

To show a case to someone outside your machine, run the reader in public mode and put a tunnel in front of it:

```bash
bash ~/.claude/skills/consilium/scripts/reader.sh --public   # prints a user and a one-time password
ngrok http 4600                                              # in a second terminal
```

Send the `https://….ngrok-free.app` URL and the password separately. Public mode requires the password on every request (set your own with `CM_READER_PASSWORD`, 12+ characters) and hides your local paths.

**Think before you share:** anyone with the URL and the password can read every case in the folder, and cases quote your code. Stop both processes (Ctrl+C) when you are done. For stronger protection, ngrok can also require a Google or GitHub login in front of the tunnel via a [traffic policy](https://ngrok.com/docs/traffic-policy/).

## Data and privacy

**Read this before using it on private code.** Every reviewer, arbiter, verifier and implementer is an agent CLI that reads your project files and sends what it reads to its provider. A panel of four means up to four providers see your code. Some free or "contributor" tiers have different data terms from paid ones; check each. Use `CM_REVIEWERS=` / `--plan` to control who is in.

## Safety model

- Reviewers, arbiters and verifiers are told not to modify code; only the implementer changes files, only inside the worktree you give it, only what the confirmed decision authorizes. It never commits, pushes or switches branches.
- Codex runs with `--sandbox workspace-write`; Claude in headless mode runs with an explicit tool allowlist (read/write/edit/search, plus shell only for verifiers and the implementer). Verifiers and the implementer can run commands: give them a worktree, not your only copy.
- Arbiters write to a candidate file, never to `decision.md`; the candidate is published only after its structure validates, and the live file is restored byte-for-byte if an arbiter touched it.
- The "incomplete panel" note is written by the script from what exists on disk, never by a model.
- A decision is always a draft with a banner; the human confirms it.

## Layout

```
skills/consilium/
  SKILL.md                 the skill (Claude Code and Codex read the same file)
  agents/openai.yaml       Codex metadata: not auto-invoked
  scripts/                 init-case, run-reviewers, run-reviewer, watch-and-decide,
                           write-decision, implement, verify, lib.sh, mock-agent
  scripts/adapters/        one file per agent CLI
  reader/                  local web reader (reader.sh starts it)
  lang/  templates/        wording per language
  consilium.example.conf
install.sh   tests/   docs/   examples/
```

## Tests

```bash
bash tests/run.sh
```

Syntax check, `shellcheck` (if installed), and end-to-end runs on the mock adapter: pipeline in both languages, arbiter fallbacks, live-file protection, timeouts, implement/verify, safe config parsing. No network, no model calls.

## Status

The scripts and the mock pipeline are tested; the `claude`, `codex`, `opencode` and `deepseek` adapters wrap real CLIs whose flags change between versions, so run `--plan` first and try a small question. Issues with CLI versions are welcome.

## License

[MIT](LICENSE)

# Development Principles

This repo packages the AI-server working style. Keep it clean, generic, and
secret-free.

## Default Style

Use `caveman lite`: short, direct, no filler, still professional and precise.
This is a default for assistant behavior and Telegram bot text. Do not make the
user explicitly ask for it.

## Codex Permissions

Default server Codex config is intentionally full access:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"

[sandbox_workspace_write]
network_access = true
```

`danger-full-access` is the real full-access mode. The
`sandbox_workspace_write.network_access` block is kept as an explicit fallback
for sessions or clients that downgrade to `workspace-write`.

## Codex Daemon And Run Stability

After ChatGPT device login, Codex remote control must be durable:

- run `codex app-server daemon bootstrap --remote-control`;
- run `codex app-server daemon restart`;
- enable `codex-app-server-daemon.service`;
- enable `codex-app-server-healthcheck.timer`;
- verify with `ai-codex-health`.

Keep the global `@openai/codex` npm package current enough to match the managed
app-server version. Version skew is not usually the root cause of stopped runs,
but matching versions removes one avoidable variable during diagnosis.

When investigating "codex run stopped", first check resources and daemon health,
then inspect CLI/session logs through summaries. Never dump raw
`~/.codex/sessions/**/*.jsonl`, screenshots, base64, or broad recursive `rg`
results into the agent context. A stopped run can be caused by huge tool outputs
ballooning the next turn to 150k+ input tokens inside a 258k context window.
Prefer:

```bash
ai-codex-health
jq -r 'select(.type=="event_msg") | [.timestamp, .payload.type] | @tsv' \
  ~/.codex/sessions/YYYY/MM/DD/*.jsonl | tail -n 200
```

If a session has no final `task_complete` and token counts are already very
large, assume context/tool-output pressure until daemon, resource, auth, and
rate-limit checks show otherwise.

## LLM Wiki Discipline

Every real repo has:

- `README.md` as the source of truth for that level;
- `AGENTS.md` pointing Codex to `README.md` and `DEV.md`;
- `CLAUDE.md` containing `@README.md`;
- `DEV.md` when there are development, deploy, env, or system rules.

README is an index, not a diary. Plans, meeting notes, transcripts, and history
belong in separate files only when actually useful.

Minimize folders. Create a folder only when it owns logic, data, or docs that
need a separate README.

## OpenSpec

OpenSpec is automatic:

- unclear feature or behavior change: explore/propose;
- existing approved change: apply;
- completed and verified change: archive;
- one-off diagnostics and read-only answers: no OpenSpec.

Users do not need to say "OpenSpec".

## Repo Creation

The agent decides:

- new standalone capability, bot, API, worker, UI, scheduled job, or deployable
  unit: create a new microservice repo;
- change inside an existing service: use that repo;
- cross-repo infrastructure: root `GIT/` index repo.

New assistant repos default to `GIT/assistants/<name>`.

## Git

- Tracked code/docs/scripts/systemd move through git.
- `.env`, tokens, runtime state, logs, private exports, local caches never enter
  git.
- Server may autosync generated non-secret artifacts.
- Prefer account-level SSH keys for Git providers; deploy keys only when repo
  boundaries require them.

## Windows Station

- Windows is a station/client by default, not the execution host.
- Keep repos, secrets, `.env-*`, services, daemon state, Telegram, OpenSpec, and
  long-running work on the Ubuntu server.
- Local Windows commands are for station setup, SSH checks, editor setup, and
  thin wrappers only.
- If the user does not explicitly ask for local Windows execution, use SSH or
  editor Remote SSH into the server and work under `~/GIT`.

## Env

Root shared providers:

- `GIT/.env-openai`
- `GIT/.env-anthropic`
- `GIT/.env-gemini`
- `GIT/.env-github`
- `GIT/.env-gitlab`
- `GIT/.env-telegram`

Service-specific tokens live in the service repo `.env`.

Load order for bots:

1. root shared provider env;
2. shared assistants env;
3. service `.env`.

## Telegram Bots

- Owner allowlist by chat id.
- `/getid` can work before allowlist; real commands cannot.
- Text, voice, and audio are first-class inputs.
- Telegram `.oga`/`.opus` voice files should be passed as `.ogg` to
  transcription APIs.
- Use HTML parse mode with escaped dynamic text.
- Error messages should explain what failed without leaking secrets.

After the core server install, always guide the user through BotFather unless
they explicitly skip Telegram. First create the control bot. Then ask whether to
create another assistant bot. Good default idea: personal diary with AI comments,
weekly reflection, and voice input.

## Logging

All services log to journald by default. Log incoming command ids, action names,
external API status, and errors. Do not log tokens, full private message bodies,
or private file paths.

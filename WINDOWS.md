# Windows Station Setup

Windows is a station/client in this kit, not the source of truth. The Ubuntu AI
server owns repos, secrets, env files, services, Codex daemon state, Telegram,
OpenSpec, and long-running work. Windows provides SSH, Git, Cursor/VS Code, and
thin commands that forward work to the server.

Default rule: unless the user explicitly asks for local Windows work, run coding,
git provider setup, repo creation, env changes, services, and Codex tasks on the
Ubuntu server under `~/GIT`.

## Install

Open PowerShell and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\bootstrap.ps1 -ServerHost <SERVER_IP_OR_HOST> -ServerUser <LINUX_USER>
```

If the server user is not known yet, use the OpenAI or Claude login/email to pick
a personal Linux username. For example, `ivan.petrov@example.com` becomes
`ivan-petrov`. Avoid generic users such as `ai`.

## What The Script Does

- Installs or checks Git for Windows, PowerShell 7, Windows Terminal, OpenSSH,
  Node.js LTS, local Codex CLI, and Cursor/VS Code when available.
- Creates or reuses an SSH key under `%USERPROFILE%\.ssh`.
- Writes a stable SSH profile named `ai-server`.
- Adds `ServerAliveInterval`, `ServerAliveCountMax`, and `TCPKeepAlive`.
- Creates thin wrappers:
  - `ai-shell.ps1`: opens an interactive server shell in `~/GIT`.
  - `codex-server.ps1`: runs Codex on the server, not on Windows.
- Verifies SSH and server-side Codex health.

## Expected Daily Use

```powershell
ai-shell
```

or:

```powershell
codex-server exec "Reply exactly: CODEX_OK"
```

For editor work, use Cursor or VS Code Remote SSH and open:

```text
ai-server:~/GIT
```

Do not store `.env-*`, provider tokens, private service configs, repo state, or
long-running processes on Windows unless the user explicitly requests a local
Windows setup.

## Verify

```powershell
.\windows\verify.ps1 -HostAlias ai-server
```

Expected checks:

- `ssh ai-server "echo SSH_OK"` works.
- `ssh ai-server "cd ~/GIT && pwd"` works.
- `ssh ai-server "codex --version"` works.
- `ssh ai-server "codex login status"` works after device login.
- `ssh ai-server "codex app-server daemon version"` works after daemon setup.

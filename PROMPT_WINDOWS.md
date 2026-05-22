# Prompt To Set Up A Windows Station

You are setting up my Windows machine as a thin station for my Ubuntu
Codex/Claude AI server. Work end to end. Do not turn Windows into the source of
truth unless I explicitly ask for local Windows execution.

Goal:

- Windows has Git, OpenSSH Client, PowerShell 7, Windows Terminal, Cursor/VS
  Code, Node.js LTS, and local Codex CLI.
- SSH profile `ai-server` is configured with stable keepalive.
- `ai-shell` opens an interactive shell on the Ubuntu server under `~/GIT`.
- `codex-server` forwards Codex commands to the Ubuntu server.
- Repos, secrets, `.env-*`, services, agents, daemon state, and long-running
  tasks remain on the Ubuntu server.

First ask me:

1. Server IP/hostname.
2. Linux username on the server. If I did not choose one, derive it from my
   OpenAI or Claude login/email, for example `ivan.petrov@example.com` becomes
   `ivan-petrov`. Do not use generic names such as `ai`.
3. Whether I already have an SSH key for this server.
4. Whether to install Cursor, VS Code, or both.

Implementation:

1. Run `windows/bootstrap.ps1` with the server host and user.
2. If SSH access is not yet available, print the generated public key and tell
   me where to add it.
3. Verify:
   - `ssh ai-server "echo SSH_OK"`
   - `ssh ai-server "cd ~/GIT && pwd"`
   - `ssh ai-server "codex --version"`
   - `ssh ai-server "codex login status"`
   - `ssh ai-server "codex app-server daemon version"`
4. Explain daily use:
   - `ai-shell` for server shell;
   - `codex-server ...` for forwarding Codex to the server;
   - Cursor/VS Code Remote SSH into `ai-server:~/GIT`.

Default behavior:

- If a task touches code, git, deploy, env, services, daemon, agents, Telegram,
  OpenSpec, or repo creation, do it on the Ubuntu server.
- Use local Windows only for station setup, SSH checks, editor setup, and thin
  wrappers.

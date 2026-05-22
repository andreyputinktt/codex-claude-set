# Install Flow

This file is for the Codex agent that performs setup. The employee normally uses
[PROMPT.md](PROMPT.md), not this file.

## 1. Choose Server

If this is a new Ubuntu server, first verify SSH stability. Ubuntu defaults can
drop long SSH sessions, so check or configure keepalive before package install,
copying large files, or running the bootstrap script. Keep the current SSH
session open until a second login works.

Collect:

- IP or hostname;
- OpenAI or Claude login/email to derive a personal default Linux username;
- target Linux username, if explicitly different from that default;
- whether this is KT-managed;
- auth method.

KT-managed:

- generate or reuse an SSH public key locally;
- give the Timofeev message from `README.md`;
- wait for access.

Non-KT:

- password auth is OK for first bootstrap;
- configure server keepalive;
- generate account SSH keys during bootstrap;
- recommend key-only SSH after verification.

## 2. Copy Kit

```bash
rsync -az --exclude .git ./codex-claude-set/ <USER>@<HOST>:/tmp/codex-claude-set/
ssh <USER>@<HOST> 'sudo bash /tmp/codex-claude-set/bootstrap.sh'
```

If only root is available:

```bash
rsync -az --exclude .git ./codex-claude-set/ root@<HOST>:/tmp/codex-claude-set/
ssh root@<HOST> 'bash /tmp/codex-claude-set/bootstrap.sh'
```

## 3. Bootstrap Answers

Use defaults unless the user gave specific values.

- `SETUP_USER`: employee Linux login. Default to a sanitized OpenAI or Claude
  login/email, for example `ivan.petrov@example.com` -> `ivan-petrov`. Do not
  use generic names such as `ai`.
- `GIT_ROOT`: `/home/<user>/GIT`.
- `DEFAULT_MODEL`: current Codex model available to the account.
- `TELEGRAM_BOT_TOKEN`: optional, never commit.
- `TELEGRAM_OWNER_CHAT_ID`: optional, required for bot control.
- `OPENAI_API_KEY`: optional, required for speech transcription.
- Git provider: one or more of GitHub, GitLab personal, GitLab KT.

## 4. Git Provider Access

Prefer account-level SSH keys.

GitHub:

```bash
gh auth login
gh auth setup-git
gh api user/keys -X POST \
  -f title="ai-server <HOST> <USER>" \
  -f key="$(cat ~/.ssh/github_account_ed25519.pub)"
```

GitLab personal or KT GitLab:

- add the printed public key in GitLab user preferences;
- use SSH remotes;
- if API repo creation is needed, configure `glab auth login` or a scoped token.

Do not add another person's public key. Verify with `ssh-keygen -lf` and provider
UI before saving.

## 5. Remote Codex

After packages and config:

```bash
sudo -iu <USER> codex login --device-auth
```

Give the user the URL and one-time code. When login succeeds:

```bash
sudo -iu <USER> codex app-server daemon bootstrap
sudo -iu <USER> codex app-server daemon start
sudo -iu <USER> codex app-server daemon enable-remote-control
sudo -iu <USER> codex app-server daemon restart
sudo -iu <USER> codex app-server daemon version
```

For Business/Enterprise/Edu accounts, workspace admins may need to enable Codex
Local and Remote Control permissions.

## 6. Windows Station

If the user works from Windows, configure Windows as a station/client after the
server is healthy:

```powershell
.\windows\bootstrap.ps1 -ServerHost <HOST> -ServerUser <USER>
.\windows\verify.ps1 -HostAlias ai-server
```

Windows must forward work to the Ubuntu server by default. Local Windows commands
are for station setup, SSH checks, editor setup, and thin wrappers only. Coding,
git provider setup, env files, services, daemon work, repo creation, Telegram,
and OpenSpec live on the server unless the user explicitly requests local
Windows execution.

Expected daily commands:

```powershell
ai-shell
codex-server exec "Reply exactly: CODEX_OK"
```

For Cursor/VS Code, use Remote SSH into `ai-server:~/GIT`.

## 7. Telegram Onboarding

Continue with [POST_INSTALL.md](POST_INSTALL.md).

First bot is the control bot that talks to the selected backend: Codex by
default, or Claude/Hermes/Cursor/custom command if the user chooses that.

If the user has no Telegram bot token yet, guide them through BotFather:

1. Open Telegram and start `@BotFather`.
2. Send `/newbot`.
3. Choose display name, for example `Ivan AI Server`.
4. Choose username in the format `<login>_<shortPurpose>_bot`, for example
   `ivan_codex_bot`.
5. Paste the token into the Codex chat.

Never print the token back in final output.

After the control bot works, ask whether to create another Telegram assistant.
Offer this idea:

```text
Личный дневник с ИИ-комментариями: человек пишет текстом или голосом, бот
сохраняет записи, отражает паттерны, задает вопросы, делает недельные выводы.
```

If accepted, collect requirements and create a new repo in
`GIT/assistants/<name>` with OpenSpec.

## 8. Final Checks

```bash
sudo -iu <USER> codex login status
sudo -iu <USER> codex exec --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox "Reply exactly: CODEX_OK"
sudo -iu <USER> hermes --version
systemctl status codex-app-server-daemon --no-pager
systemctl status codex-telegram-bridge --no-pager || true
systemctl status speech-transcriber --no-pager || true
```

If ChatGPT says "waiting for desktop app", restart daemon after login and verify
that the ChatGPT account is the same account used for device auth.

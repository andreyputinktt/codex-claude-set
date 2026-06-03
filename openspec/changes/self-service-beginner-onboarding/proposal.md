## Why

The current kit works when an experienced agent follows the runbook, but a
non-technical user still needs too many implicit decisions around SSH, server
choice, workspace mirroring, provider keys, and llm-wiki maintenance.

This change makes onboarding script-first: a beginner answers questions, follows
links for accounts and keys, and ends with a local workspace mirrored to the
server, strict llm-wiki docs, and optional agent/provider integrations.

## What Changes

- Add a beginner onboarding wizard for macOS/Linux that gathers server, Git,
  provider, workspace, and optional Hermes/OpenClaw preferences.
- Add a Windows PowerShell onboarding wizard with the same intent and clear
  next steps for non-technical users.
- Add SSH access preparation for personal/KT servers: generate or reuse a local
  key, print admin-ready access messages, optionally install the key with
  password access, and optionally disable password SSH after key verification.
- Add a llm-wiki index refresher that creates/checks root docs, folder README
  files, repo docs, and root README index entries.
- Add a workspace mirror helper to keep the same starter folder shape on the
  computer and server.
- Update bootstrap/new-repo flows so repo creation refreshes the llm-wiki index
  instead of leaving README updates to memory.
- Update README/PROMPT/INSTALL/WINDOWS docs so the expected path is question-led
  and understandable for non-technical users.

## Capabilities

### New Capabilities

- `beginner-onboarding`: A guided setup flow that turns account/server/provider
  answers into a configured local and server AI workspace.
- `llm-wiki-index-refresh`: Deterministic maintenance of root and repo-level
  llm-wiki files and README indexes.
- `server-access-preflight`: SSH key generation, server access instructions, and
  password-to-key migration for personal and KT-managed servers.
- `workspace-mirroring`: Creation and synchronization of the same starter folder
  structure locally and on the selected server.

### Modified Capabilities

- None.

## Impact

- Adds scripts under `scripts/` and Windows equivalents under `windows/`.
- Updates `bootstrap.sh` generated helper commands and root docs.
- Updates onboarding documentation: `README.md`, `INSTALL.md`, `PROMPT.md`,
  `WINDOWS.md`, and `PROMPT_WINDOWS.md`.
- No secrets are stored in tracked files; provider tokens continue through the
  secret setter flow.

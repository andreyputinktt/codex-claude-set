## Context

The existing flow is prompt-led: an agent reads `PROMPT.md`, asks questions, and
manually bridges gaps around local prerequisites, SSH access, workspace docs,
server mirroring, and provider secrets. That works for technical users, but a
beginner needs executable steps with clear prompts and safe defaults.

The repository already has a server bootstrap, Windows station bootstrap,
secret setter, and llm-wiki policy. The missing layer is a local onboarding
orchestrator and deterministic helpers that enforce the policy instead of
depending on agent memory.

## Goals / Non-Goals

**Goals:**

- Provide a macOS/Linux beginner wizard that asks concrete questions and calls
  deterministic helper scripts.
- Provide a Windows wizard that performs the equivalent station setup and points
  the user to server access steps.
- Generate/reuse SSH keys and print admin-ready server access instructions.
- Support password-first server access and optional migration to key-only SSH.
- Create a local starter `GIT/` folder and mirror its llm-wiki structure to the
  selected server.
- Keep the root README index and repo/folder llm-wiki files current through a
  reusable index refresher.
- Keep API keys and tokens out of tracked files by reusing the secret setter.

**Non-Goals:**

- Buying or provisioning a VPS through a provider API.
- Fully authenticating GitHub/GitLab/OAuth flows without browser/user action.
- Copying private repo contents by default during starter mirroring.
- Replacing the existing server `bootstrap.sh`; the new flow prepares and
  orchestrates around it.

## Decisions

1. Add small scripts instead of embedding more prose into `PROMPT.md`.

   Rationale: SSH key generation, README index updates, package checks, and
   rsync/ssh validation are deterministic and testable. The prompt remains a
   guide for Codex/Claude, while scripts perform repeatable actions.

2. Use marker-managed README index blocks.

   Rationale: rewriting arbitrary human README prose is risky. A managed block
   lets `ai-index-refresh` update folder/repo tables repeatedly without
   destroying custom content.

3. Mirror the starter shape, not secrets or full private content, by default.

   Rationale: a beginner needs the same root folder contract on computer and
   server. Full repo/data synchronization remains a separate explicit action
   because it can expose secrets or large private files.

4. Treat server access as a preflight separate from bootstrap.

   Rationale: if SSH is not ready, the bootstrap cannot run. The access script
   must be usable before the repository is copied to the server and must support
   KT-managed and personal servers.

5. Keep provider credentials in existing `.env-*` secret setter flow.

   Rationale: the existing scripts already handle hidden input, chmod, optional
   verification, and server upload. The onboarding wizard should call them
   instead of creating another secret path.

## Risks / Trade-offs

- [Risk] Password hardening can lock a user out if key access is not verified.
  -> Mitigation: only offer key-only SSH after a successful key login check, and
  keep the existing session open.
- [Risk] README auto-update could overwrite hand-written documentation.
  -> Mitigation: only create missing files and replace content inside managed
  marker blocks.
- [Risk] Beginner wizard cannot complete third-party account setup itself.
  -> Mitigation: print direct account/key URLs and exact public keys/messages to
  paste.
- [Risk] Package installation differs across macOS, Linux, and Windows.
  -> Mitigation: split macOS/Linux shell prerequisites from Windows PowerShell
  bootstrap and keep commands explicit.

## Migration Plan

1. Add scripts and validate syntax.
2. Install server-side helper aliases from `bootstrap.sh`.
3. Update `ai-new-repo` to run the index refresher after creating a repo.
4. Update README/PROMPT/INSTALL/WINDOWS docs to make the beginner wizard the
   first path.
5. Leave existing prompt-led flow intact as an advanced/manual fallback.

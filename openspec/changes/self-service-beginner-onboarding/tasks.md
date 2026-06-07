## 1. Implementation

- [x] Add macOS/Linux local prerequisite installer.
- [x] Add server access preflight script with SSH key generation, admin message,
      password-first key install, and optional key-only hardening.
- [x] Add llm-wiki index refresher for root docs, folder README files, repo docs,
      and managed README index blocks.
- [x] Collapse generated README index blocks into one folder table and include
      bounded Codex session hints for faster folder lookup.
- [x] Add generic llm-wiki principles: root index chooses the folder, child
      README owns details/dependencies, AGENTS/CLAUDE stay thin, no thematic
      root routing blocks, and dirty workspaces run `./deploy-server.py` or
      report the missing deploy boundary.
- [x] Add workspace mirror helper for secret-safe local-to-server starter sync.
- [x] Add macOS/Linux beginner onboarding wizard that orchestrates prerequisites,
      llm-wiki refresh, server access, workspace mirror, provider secrets, and
      backend preferences.
- [x] Add Windows beginner onboarding wrapper around existing station setup and
      key/server guidance.
- [x] Install new helpers from `bootstrap.sh` and update `ai-new-repo` to refresh
      the root llm-wiki index.
- [x] Update README, INSTALL, PROMPT, WINDOWS, and PROMPT_WINDOWS for the
      beginner question-led flow.

## 2. Verification

- [x] Run shell syntax checks for all new/changed shell scripts.
- [x] Run the llm-wiki refresher in dry-run or test root mode.
- [x] Verify OpenSpec status and task completion.

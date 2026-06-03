## ADDED Requirements

### Requirement: Guided Beginner Wizard
The system SHALL provide a macOS/Linux beginner onboarding wizard that asks a
non-technical user for local workspace, server, Git provider, optional agent
backend, and provider API-key preferences.

#### Scenario: User starts from installed Codex or Claude
- **WHEN** the user runs the beginner onboarding script from the repository
- **THEN** the script asks concrete questions and prints the next user action for
  any step that requires a browser, account page, server admin, or secret value

#### Scenario: User chooses optional providers
- **WHEN** the user chooses OpenAI, Claude/Anthropic, Gemini, GitHub, or GitLab
- **THEN** the script uses the existing secret/key flows or prints exact account
  URLs and public keys without writing secret values to tracked files

### Requirement: Local Prerequisites
The system SHALL provide a local prerequisites helper for macOS and Linux that
installs or reports required base tools for the onboarding flow.

#### Scenario: User runs prerequisites on supported OS
- **WHEN** the user runs the prerequisites helper on macOS or Linux
- **THEN** the helper installs or reports the status of git, ssh, rsync, jq,
  ripgrep, GitHub CLI, Node/npm, and OpenSpec-related tooling where available

### Requirement: Optional Agent Backend Notes
The system SHALL record whether the user wants Hermes, OpenClaw, both, or only
Codex/Claude as the initial agent backend preference.

#### Scenario: User chooses Hermes or OpenClaw
- **WHEN** the user selects Hermes, OpenClaw, or both in onboarding
- **THEN** the local setup notes capture that preference and the final output
  states which server-side bootstrap tools should be verified

## ADDED Requirements

### Requirement: Starter Workspace Mirror
The system SHALL provide a helper that mirrors the starter llm-wiki folder shape
from the local computer to the selected server.

#### Scenario: Server SSH is available
- **WHEN** the user runs the mirror helper with a local root, server, and remote
  root
- **THEN** the helper refreshes the local llm-wiki index, creates the remote root,
  copies root docs and folder README files, and runs the remote index refresher
  when available

### Requirement: Secret-Safe Mirroring
The mirror helper SHALL exclude secrets, caches, virtualenvs, node modules,
runtime logs, and git internals by default.

#### Scenario: Workspace contains ignored private files
- **WHEN** the mirror helper synchronizes the starter folder
- **THEN** tracked docs and folder shape are copied while `.env*`, private keys,
  caches, logs, and dependency folders are excluded

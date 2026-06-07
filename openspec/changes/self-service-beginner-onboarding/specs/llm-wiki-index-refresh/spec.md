## ADDED Requirements

### Requirement: Root llm-wiki Skeleton
The system SHALL provide an index refresher that creates missing root
`README.md`, `DEV.md`, `AGENTS.md`, `CLAUDE.md`, `llm-wiki.md`, and `.gitignore`
files according to the llm-wiki contract.

#### Scenario: Fresh starter folder
- **WHEN** the refresher runs on an empty starter folder
- **THEN** it creates the required llm-wiki files and standard top-level folders

### Requirement: Managed Root Index
The system SHALL maintain a single marker-managed root README index table for
top-level folders and nested child repositories.

The root README index SHALL choose the first folder to inspect. It SHALL NOT
duplicate child internals, maintain a cross-repo dependency graph, or create
separate thematic routing sections.

#### Scenario: Existing README has custom content
- **WHEN** the refresher runs on a workspace with an existing root README
- **THEN** it preserves custom content outside the managed marker block and
  updates only the generated index block

#### Scenario: Codex session hints
- **WHEN** recent local Codex session logs mention indexed folders
- **THEN** the generated index includes bounded session-path hints for those
  folders without copying chat contents into README

#### Scenario: Folder-owned dependencies
- **WHEN** a folder depends on another context, service, data source, or brand
- **THEN** that dependency is documented in the owning folder README, not in the
  root README index

### Requirement: Repo-Level Agent Files
The system SHALL create missing `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEV.md`,
and `.gitignore` files for detected child repositories without overwriting
existing files.

`AGENTS.md` and `CLAUDE.md` SHALL stay thin pointers to README/DEV; durable
facts and working preferences belong in README/DEV at the relevant level.

#### Scenario: Child repo lacks agent files
- **WHEN** the refresher detects a child git repository with missing llm-wiki
  files
- **THEN** it creates the missing files and reports the action

### Requirement: Deploy Script On Dirty Workspace
The starter development rules SHALL require agents to run `./deploy-server.py`
immediately when `git status` shows uncommitted changes. If the script is
missing, agents SHALL report that the workspace is missing its deploy boundary.

#### Scenario: Dirty workspace with deploy script
- **WHEN** an agent detects uncommitted changes in a workspace containing
  `./deploy-server.py`
- **THEN** it runs `./deploy-server.py` before leaving deployable changes local

#### Scenario: Dirty workspace without deploy script
- **WHEN** an agent detects uncommitted changes and `./deploy-server.py` is
  missing
- **THEN** it reports the missing deploy boundary instead of silently skipping
  deploy

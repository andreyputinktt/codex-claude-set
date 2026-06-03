## ADDED Requirements

### Requirement: Root llm-wiki Skeleton
The system SHALL provide an index refresher that creates missing root
`README.md`, `DEV.md`, `AGENTS.md`, `CLAUDE.md`, `llm-wiki.md`, and `.gitignore`
files according to the llm-wiki contract.

#### Scenario: Fresh starter folder
- **WHEN** the refresher runs on an empty starter folder
- **THEN** it creates the required llm-wiki files and standard top-level folders

### Requirement: Managed Root Index
The system SHALL maintain a marker-managed root README index of top-level folders
and child repositories.

#### Scenario: Existing README has custom content
- **WHEN** the refresher runs on a workspace with an existing root README
- **THEN** it preserves custom content outside the managed marker block and
  updates only the generated index block

### Requirement: Repo-Level Agent Files
The system SHALL create missing `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEV.md`,
and `.gitignore` files for detected child repositories without overwriting
existing files.

#### Scenario: Child repo lacks agent files
- **WHEN** the refresher detects a child git repository with missing llm-wiki
  files
- **THEN** it creates the missing files and reports the action

## ADDED Requirements

### Requirement: SSH Key Preparation
The system SHALL provide a server access preflight helper that creates or reuses
a local SSH key and prints the public key for server access.

#### Scenario: User has no existing key
- **WHEN** the user runs server access preflight without an existing key file
- **THEN** the helper creates an Ed25519 key and prints the public key

#### Scenario: KT-managed server
- **WHEN** the user marks the server as KT-managed
- **THEN** the helper prints an admin-ready access request containing server,
  Linux user, sudo requirement, and the public key

### Requirement: Password-First Migration
The system SHALL support personal servers where password SSH is available for
first setup.

#### Scenario: User has password SSH access
- **WHEN** the user chooses password-first setup
- **THEN** the helper offers to install the public key to `authorized_keys` and
  verifies key-based SSH before continuing

#### Scenario: User chooses key-only SSH
- **WHEN** key-based SSH has been verified and the user opts to disable password
  login
- **THEN** the helper writes a dedicated sshd config drop-in, validates sshd
  config, reloads sshd, and runs a second key-based SSH check

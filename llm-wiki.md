# LLM Wiki Contract

This is the compact navigation contract for Codex, Claude Code, OpenCode, and
other agents.

## Start Order

1. Read root `README.md`.
2. If the task touches code, deploy, env, git, or server setup, read `DEV.md`.
3. Identify the owning repo.
4. Read that repo's `README.md`.
5. Only then inspect code.

Do not start with recursive directory scans unless the index is missing or stale.

## File Contract

`README.md`:

- what this level contains;
- how to run or enter deeper docs;
- external dependencies;
- links to real details.

`AGENTS.md`:

```markdown
# Agent guide
@README.md

Dev rules: [DEV.md](DEV.md).
```

`CLAUDE.md`:

```markdown
@README.md
```

`DEV.md`:

- development workflow;
- env/secrets;
- deploy/systemd;
- Git provider rules;
- OpenSpec policy;
- repo creation policy.

## README Rules

1. Index, not diary.
2. Only this level.
3. One fact in one place.
4. Loose coupling by links.
5. Minimal top level.
6. Folders with logic get their own README.
7. Remove stale paths immediately.

## Closeout Checklist

- README still current.
- New logic folder has README/AGENTS/CLAUDE.
- Startup/deploy changes are documented.
- Secrets are ignored.
- OpenSpec status is handled when behavior changed.


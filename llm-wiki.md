# LLM Wiki Contract

This is the compact navigation contract for Codex, Claude Code, OpenCode, and
other agents.

## Start Order

1. Read root `README.md`.
2. If the task touches code, deploy, env, git, or server setup, read `DEV.md`.
3. Identify the owning folder or repo from the root index.
4. Read that folder's or repo's `README.md`.
5. Only then inspect code.

Do not start with recursive directory scans unless the index is missing or stale.

## File Contract

`README.md`:

- what this level contains;
- how to run or enter deeper docs;
- links to real details.

Root `README.md` answers only "which folder should I open first". It does not
describe child internals, does not maintain a cross-repo dependency graph, and
does not add separate thematic routing sections. Put routing hints in the single
folder index table, especially the cases/search-hints column.

Dependencies live at the owning level: if `content-service/` depends on
`profile-context/`, document that in `content-service/README.md` or the
relevant owner README, not in the root index.

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
8. Working preferences and durable facts live in README/DEV at the relevant
   level. `AGENTS.md` and `CLAUDE.md` stay thin pointers, not knowledge bases.

## Closeout Checklist

- README still current.
- New logic folder has README/AGENTS/CLAUDE.
- Startup/deploy changes are documented.
- Secrets are ignored.
- If uncommitted changes exist, run `./deploy-server.py` immediately. If the script is missing, report that the workspace is missing its deploy boundary.
- OpenSpec status is handled when behavior changed.

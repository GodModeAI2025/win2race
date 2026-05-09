# Advanced Mode Task Format

Win-to-Race currently prioritizes Markdown task files.

Required sections:

- `## Repository`: Git URL or local repository path.
- `## Title`: Short task title used for task naming and branch slugs.
- `## Description`: Full problem statement passed to all selected agents.

Optional sections:

- `## Constraints`: Bullet list or free text constraints.

Example:

```markdown
# task.md

## Repository
https://github.com/org/project

## Title
Fix websocket reconnect issue

## Description
Users lose connection after sleep mode.

## Constraints
- Do not modify auth layer
- Keep API compatibility
- Add tests
```

Future parser candidates are YAML, JSON, and TOML. Markdown stays first because it is easy for developers and agents to read, review, and version.

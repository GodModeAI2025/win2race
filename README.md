# Win-to-Race

Win-to-Race is a native macOS app that orchestrates multiple coding CLIs on the same real software task. Each agent gets its own branch, workspace, logs, ADR, runtime report, and feedback record.

## Current V1 Scope

- Native SwiftUI macOS app with Simple Mode and Advanced Mode.
- Automatic CLI discovery for Claude, Gemini, Codex, aider/OpenCode-based providers, and prepared frontier-provider slots.
- File-backed Markdown persistence under `~/Documents/Win2Race/workspace`.
- Per-agent workspace, branch naming, runtime logs, generated ADR, and feedback files.
- Interactive session handling with live logs and a pending-question state.
- Secure API-key storage through the macOS Keychain.
- Markdown task parser for Advanced Mode.

## Advanced Task Format

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

See [docs/advanced-task-format.md](docs/advanced-task-format.md) for details.

## Static Overview

The repository includes [index.html](index.html) as a lightweight project overview page. It has no external dependencies and can be opened directly from the repository root.

## Build And Run

Use the project-local run entrypoint:

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM GUI target, stages `dist/Win2Race.app`, and launches the app as a proper macOS application bundle.

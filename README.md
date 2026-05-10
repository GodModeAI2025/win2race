# Win-to-Race

Win-to-Race is a native macOS app that orchestrates multiple coding CLIs on the same real software task. Each agent gets its own branch, workspace, logs, ADR, runtime report, and feedback record.

## Current V1 Scope

- Native SwiftUI macOS app with Simple Mode and Advanced Mode.
- Automatic CLI discovery for Claude, Gemini, Codex, aider/OpenCode-based providers, and prepared frontier-provider slots.
- Actionable Setup overview that tells the user what to install, save, test, or fix next before the app is green.
- File-backed Markdown persistence under `~/Documents/Win2Race/workspace`.
- Per-agent workspace, branch naming, runtime logs, generated ADR, and feedback files.
- Runtime registry with CLI/profile health, capabilities, and per-agent command overrides.
- Structured per-run `events.jsonl` beside `session.log` for machine-readable lifecycle, stdout, stderr, git, question, error, and heartbeat events.
- Agent profiles for model override, extra CLI arguments, timeout, Git commit identity, and per-agent SSH key preparation.
- Workspace root visibility and safe artifact cleanup for regenerable directories.
- Interactive session handling with live logs and a pending-question state.
- Secure API-key storage through the macOS Keychain, plus per-token test buttons for auth, access, and budget/quota checks.
- Copyable diagnostics for failed setup, provider, runtime, parser, and process errors.
- Markdown task parser for Advanced Mode.

## Setup Readiness

The Setup screen is intentionally strict. Win-to-Race only asks for provider tokens needed by installed/configured runtimes. A provider token is not considered green just because it exists in the macOS Keychain. Each visible token must be saved and then tested.

The overview tells the user the next concrete action:

- install a missing CLI
- open the correct provider key page
- paste and save a missing token
- run the token test
- fix ENV syntax
- copy a failed diagnostic message

This avoids the old failure mode where setup looked ready but the first agent run failed because the key was invalid, had no model access, or had no usable budget.

## API Token Tests

Each saved API token has its own `Test` button in Setup. The test performs the smallest practical provider check and stores a copyable result.

Supported active test plans:

| Key | Provider | Check |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Claude/Anthropic | Minimal Claude Messages request |
| `OPENAI_API_KEY` | OpenAI | Minimal Responses API request |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | Google | Minimal Gemini generateContent request |
| `GROQ_API_KEY` | Groq | Minimal OpenAI-compatible chat request |
| `DEEPSEEK_API_KEY` | DeepSeek | Minimal chat request |
| `OPENROUTER_API_KEY` | OpenRouter | Key metadata endpoint with usage/limit parsing |

Most provider tests make a minimal model call and can consume a tiny amount of budget. OpenRouter uses its key metadata endpoint where possible and marks exhausted limits as not green.

Qwen, Kimi, and GLM use OpenRouter in V1. DashScope is intentionally not required, and direct Moonshot/Z.ai keys are not part of the default green path.

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

## Multica-Inspired Foundations

W2R adopted selected local-first ideas from Multica: runtime health, structured run events, agent profiles, per-agent Git SSH preparation, heartbeat metadata, and safe workspace cleanup. See [docs/multica-learnings.md](docs/multica-learnings.md).

## Static Overview

The repository includes [index.html](index.html) as a lightweight project overview page. It has no external dependencies and can be opened directly from the repository root.

## Build And Run

Use the project-local run entrypoint:

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM GUI target, stages `dist/Win2Race.app`, and launches the app as a proper macOS application bundle.

For validation:

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

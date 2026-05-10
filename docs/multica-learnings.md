# Multica Learnings Applied

Win-to-Race remains a native, local macOS app. The useful Multica ideas are implemented as local-first foundations rather than a web/server/daemon rewrite.

## Implemented

- Runtime registry: W2R now tracks local runtime health, command path, strategy, capabilities, and profile-derived overrides.
- Structured run events: every new run writes `events.jsonl` next to `session.log`.
- Agent profiles: each agent can define a CLI override, model override, extra shell-style arguments, timeout, Git author identity, and SSH identity path.
- Agent Git identity preparation: when an SSH identity path is configured, W2R applies `GIT_SSH_COMMAND` during clone and persists `core.sshCommand` in the worktree.
- Workspace cleanup: W2R can remove regenerable artifacts such as `node_modules`, `.next`, `.turbo`, `.build`, and `DerivedData` while preserving `.git`, logs, ADRs, results, and feedback.
- Heartbeat metadata: runs now persist `lastOutputAt` and `lastHeartbeatAt`.

## Deliberately Not Copied

- No web frontend, Go backend, PostgreSQL, or cloud daemon in V1.
- No automatic model routing from learning data yet.
- No scheduled autopilot execution yet.

## Next Candidates

- Configurable workspace root migration.
- First-class repo profiles with per-repo SSH keys and Git remotes.
- A reusable-pattern library generated from accepted ADRs and feedback.
- Sequenced event filters in the UI.

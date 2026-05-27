# FloatMon Agent Monitor Design

## Goal

Add an agent monitoring mode to FloatMon without removing the existing app resource monitor. The floating ball currently represents the most active app. Users should be able to double-click the ball to switch between app monitoring and agent monitoring.

The architecture should support multiple coding agents over time. The MVP only implements Codex monitoring.

## Current Project Context

FloatMon is a SwiftPM macOS app. `ProcessStore` samples running apps, `IslandWindow` owns the floating panel, and `IslandView` renders the collapsed ball and expanded app list. The app already uses a small service/store/view split and should keep that shape.

Codex exposes useful local data:

- `~/.codex/hooks.json` can register command hooks for events such as `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, and `Stop`.
- `~/.codex/state_5.sqlite` contains thread metadata including title, cwd, updated time, and `tokens_used`.
- `~/.codex/goals_1.sqlite` contains goal objective, status, token budget, tokens used, and elapsed time.

## User Experience

The collapsed floating ball has two modes:

- App mode: existing behavior. It shows the featured app icon and resource pressure dot.
- Agent mode: it shows an agent-oriented Codex status mark, with a visual indication for recent activity, waiting for permission, running tool use, or idle.

Double-clicking the floating ball switches between modes. Existing dragging and click-to-expand behavior should remain intact.

When expanded, the panel exposes both monitoring surfaces. The MVP can show the selected mode directly after expansion, with a compact segmented control or equivalent switch for `Apps` and `Agent` so users are not trapped in one view.

## Hook Registration

FloatMon should not silently edit agent configuration. On startup, it checks whether the FloatMon Codex hook is registered. If it is missing, the app prompts the user to register it.

If the user agrees:

1. Create a timestamped backup of the original `~/.codex/hooks.json`.
2. Merge FloatMon hook entries into the existing hook lists without deleting or replacing existing hooks.
3. Preserve existing event matchers and hook order where possible.
4. Report success or failure in the app UI.

If registration fails or the user declines, FloatMon still runs. Codex monitoring falls back to sqlite polling and shows that live hooks are not active.

## Data Flow

Codex monitoring has two inputs:

- Live hook events: a small local hook command receives Codex hook payloads and writes normalized events to `~/.codex/floatmon/events.jsonl` plus the latest summary to `~/.codex/floatmon/state.json`.
- Snapshot polling: FloatMon reads Codex sqlite files to enrich the current agent state with thread title, cwd, token usage, goal status, token budget, and elapsed time.

The hook writer should be small and deterministic. It should append events, update a latest-state file atomically, and avoid logging sensitive prompt content unless the hook payload already exposes only safe metadata. The UI should prefer metadata such as event type, tool name, thread id, timestamps, status, and counters.

## Components

New model layer:

- `AgentProvider`: identifies supported providers. MVP: `.codex`.
- `AgentMode`: app monitoring or agent monitoring.
- `AgentEvent`: normalized live event with provider, event type, timestamp, optional thread id, optional tool name, and status.
- `AgentSnapshot`: current provider status, thread summary, usage summary, goal summary, recent events, and hook registration status.

New services:

- `CodexHookRegistrationService`: checks, backs up, and merges `~/.codex/hooks.json`.
- `CodexHookWriter`: command entry point used by Codex hooks to write event files.
- `CodexSnapshotReader`: reads `state_5.sqlite`, `goals_1.sqlite`, and FloatMon event files.

New store:

- `AgentStore`: periodically refreshes `AgentSnapshot`, exposes hook registration state, and handles registration prompts/results.

View changes:

- `IslandView` owns the current monitor mode and passes it into header/list rendering.
- Add an `AgentMonitorView` for the expanded agent panel.
- Add a startup hook registration prompt when Codex hooks are missing.

## Error Handling

Codex files may be missing, locked, or in a newer schema. The app should show a degraded state instead of crashing. Each reader should treat missing files as unavailable data and return a clear status.

Hook registration errors should include the failed operation: backup, parse, merge, or write. If backup fails, registration must stop before modifying `hooks.json`.

Malformed event lines should be ignored individually. A bad event must not prevent newer valid events from loading.

## Testing

Focused tests should cover:

- Hook JSON merge preserves existing hooks and adds FloatMon hooks once.
- Hook JSON merge is idempotent.
- Backup path generation is timestamped and does not overwrite existing backups.
- Event parsing ignores malformed lines and keeps valid events.
- Snapshot mapping handles missing sqlite files.

Manual verification should cover:

- `make build`
- startup prompt appears when Codex hook is missing
- hook registration creates a backup before changing `hooks.json`
- double-click switches between app and agent modes
- expanded agent panel shows Codex usage and task status

## Scope

In scope for MVP:

- Codex provider only.
- Startup prompt for hook registration.
- Backup and merge of Codex hook config.
- Agent mode UI with Codex thread, usage, goal, and recent event state.

Out of scope for MVP:

- Claude Code provider implementation.
- Network APIs or cloud sync.
- Editing existing Codex auth files.
- Displaying full prompt text or sensitive auth data.

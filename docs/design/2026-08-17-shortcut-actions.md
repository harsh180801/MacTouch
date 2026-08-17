# Phase 8 — Shortcut actions design

**Date:** 2026-08-17  
**Status:** Approved for implementation  
**Location:** `docs/design/`

## Problem

MacTouch now detects gestures in a menu-bar app, but recognized gestures do not trigger user automation yet. We need a safe first action capability that maps single/double/triple gestures to macOS Shortcuts by name.

## Goals (initial slice)

- Add per-gesture shortcut mappings (single/double/triple)
- Execute shortcuts with `/usr/bin/shortcuts run <name>` via `Process`
- Add safety guardrails:
  - global enable toggle
  - configurable cooldown (default ~1.2s)
  - skip when an action is already running
- Surface action status in UI (success / failure / skipped reason)
- Keep implementation in `MacTouchApp` for now (no `MacTouchCore` side-effect APIs yet)

## Non-goals (this slice)

- AppleScript fallback or alternate execution paths
- Action queueing / retries
- Multi-action chains per gesture
- CLI-triggered actions
- System mute / app launch / notifications (possible later actions)

## Decisions

| Topic | Choice |
|-------|--------|
| Mapping | Configurable per gesture kind |
| Executor | `shortcuts run` via `Process` |
| Guardrails | Cooldown + in-flight skip |
| Placement | `MacTouchApp` only |
| Persistence | separate app action settings file (`~/.config/MacTouch/actions.json`) |

## Architecture

```text
AppViewModel
  ├─ ListeningEngine (existing) emits TapGestureEvent
  ├─ ActionSettingsStore (load/save actions.json)
  └─ ShortcutActionDispatcher
       └─ ProcessRunner (/usr/bin/shortcuts run <name>)
```

## Data model

`ActionSettings` (Codable):

- `enabled: Bool`
- `singleShortcutName: String?`
- `doubleShortcutName: String?`
- `tripleShortcutName: String?`
- `cooldownSeconds: Double`

Validation:
- cooldown finite and > 0
- shortcut names are trimmed; empty treated as unmapped

## Runtime behavior

On recognized gesture:
1. If actions disabled → skipped (`disabled`)
2. Resolve mapping for gesture kind; if missing → skipped (`unmapped`)
3. If dispatcher already running → skipped (`busy`)
4. If now - lastRun < cooldown → skipped (`cooldown`)
5. Run shortcut via `Process`
6. Update last action status in UI

No queueing: extra gestures during a run are intentionally dropped as `busy`.

## UI additions (MenuBar popover)

- Toggle: Enable Shortcut Actions
- Text fields: Single / Double / Triple shortcut names
- Cooldown slider (0.5s…5.0s)
- Test buttons per mapping (“Run now”)
- Last action status line

## Errors and observability

- Missing `shortcuts` binary → clear failure message
- Non-zero exit code → include stderr summary
- Skipped outcomes are not errors; still visible in status line

## File layout

```text
docs/design/2026-08-17-shortcut-actions.md
Sources/MacTouchApp/ActionSettings.swift
Sources/MacTouchApp/ShortcutActionDispatcher.swift
Sources/MacTouchApp/AppViewModel.swift
Sources/MacTouchApp/ContentView.swift
Tests/MacTouchAppTests/ShortcutActionDispatcherTests.swift
Tests/MacTouchAppTests/ActionSettingsStoreTests.swift
Package.swift (add MacTouchAppTests target)
```

## Testing

Unit tests for:
- disabled / unmapped / cooldown / busy skip
- success path
- non-zero exit / launch failure path
- action settings load/save

Manual checks:
- Map double-tap to known shortcut and trigger from live gestures
- Verify cooldown and busy behavior in status line

## Success criteria

- Gesture mappings invoke expected shortcuts reliably
- Cooldown and busy guard prevent accidental repeated triggers
- Failures are readable from app UI
- Existing detection/calibration features remain intact (`swift test` green)

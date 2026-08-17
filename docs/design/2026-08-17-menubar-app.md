# Phase 7 — Menu-bar app design

**Date:** 2026-08-17  
**Status:** Approved for implementation  
**Location:** `docs/design/` (product design docs; not Superpowers skill artifacts)

## Problem

Phase 6 delivers CLI calibration and gesture detection. Day-to-day use needs a lightweight macOS menu-bar UI: start/stop listening, see gesture counts, tweak settings, and run calibration without Terminal.

## Goals (MVP)

- SwiftPM executable `MacTouchApp` with SwiftUI `MenuBarExtra` popover
- Start/stop chassis-tap listening (reuse `MacTouchCore`)
- Counters for single / double / triple + last gesture
- Sliders for `minAbsoluteThresholdG`, `groupingWindow`, `gestureCooldown`
- Persist via shared `MacTouchSettings` JSON at `~/.config/MacTouch/settings.json` (same as CLI)
- In-app calibration wizard driving `CalibrationService`, then save JSON
- Non-root first; no system actions (Phase 8)

## Non-goals (this pass)

- Waveform / debug event log (later UI pass)
- Launch at Login, App Store signing, full `.app` bundle polish
- UserDefaults as primary store (JSON remains source of truth)
- Phase 8 actions (mute, Shortcuts, etc.)
- Embedding CLI as a subprocess

## Decisions

| Topic | Choice |
|-------|--------|
| Packaging | SwiftPM executable target `MacTouchApp` |
| Scope | Focused MVP (no waveform yet) |
| Calibration | In-app wizard + shared JSON with CLI |
| Chrome | `MenuBarExtra` popover (`.window` style for controls) |
| Architecture | `AppViewModel` + `ListeningEngine` + `SettingsStore` |

## Architecture

```text
MacTouchApp (SwiftUI MenuBarExtra)
  └─ AppViewModel (@MainActor, Observable)
        ├─ SettingsStore  → MacTouchSettings JSON
        ├─ ListeningEngine → SensorService + signal/tap/gesture pipeline
        └─ CalibrationCoordinator / sheet → CalibrationService
```

## Behavior

- Launch: load settings JSON if present; else defaults. Activation policy: accessory (menu-bar only).
- Start: open sensor, apply settings to detector/gesture configs, count gestures on main actor.
- Stop: close sensor; keep counters until reset.
- Sliders: update in-memory settings; save JSON on change (debounce OK).
- Calibrate…: modal/sheet with Phase 6 stage prompts; on success save JSON and refresh; on failure do not overwrite.

## File layout

```text
docs/design/2026-08-17-menubar-app.md
Sources/MacTouchApp/
  MacTouchApp.swift
  AppViewModel.swift
  SettingsStore.swift
  ListeningEngine.swift
  ContentView.swift
  CalibrationSheet.swift
Package.swift  # MacTouchApp product + target
```

## Testing

- Unit tests for SettingsStore load/save/apply (temp directory)
- Manual: `swift run MacTouchApp`; listen; calibrate; confirm CLI `--gestures --config` reads same file
- `swift test` remains green; `MacTouchProbe` unchanged in behavior

## Success criteria

- Menu-bar app runs without root
- Start/stop + counters work for single/double/triple
- Settings persist to shared JSON and affect recognition
- In-app calibrate updates that JSON
- Docs mark Phase 7 MVP done; waveform deferred

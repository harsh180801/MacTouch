# Phase 6 — Calibration design

**Date:** 2026-08-16  
**Status:** Approved for implementation planning  
**Repo:** MacTouch (`MacTouchCore` + `MacTouchProbe`)

## Problem

Chassis-tap detection works (Phases 1–5), but defaults for strength threshold and gesture timing do not match every user’s tap style. In particular, double taps around **~0.15 s** apart need a grouping window that is long enough to merge doubles but short enough that singles do not feel excessively delayed.

## Goals

- Deliver a **live guided calibration wizard** that measures idle noise, intentional single taps, and intentional double taps.
- Produce **recommended settings** for detection threshold, gesture grouping window, and gesture cooldown.
- Persist settings as **Codable JSON** via a shared `MacTouchSettings` model that Phase 7 can later map to UserDefaults without changing core types.
- Expose calibration through **`MacTouchCore` + CLI** (`--calibrate`), and load settings via `--config` for `--detect` / `--gestures`.

## Non-goals (Phase 6)

- SwiftUI / menu-bar UI
- Typing or trackpad rejection stages
- Offline / replay-based calibration
- Persisting via UserDefaults (JSON only for now)
- Changing sensor HID access or inventing a second tap detector

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Surface | Library (`CalibrationService` et al.) + CLI `--calibrate` |
| Stages | Idle → singles → doubles |
| Persistence | Print recommendations + write JSON; shared settings shape for Phase 7 |
| Capture | Live wizard only |
| Approach | Stats on existing signal → tap pipeline (Approach 1), with a temporarily more sensitive detector during collection |

## Architecture

```text
SensorService
  → SignalProcessor → TapDetector (calibrate-sensitive config)
      → CalibrationSession (stage machine)
          → CalibrationAnalyzer
              → MacTouchSettings (Codable)
                  → print + write JSON
```

### Components

| Type | Module | Responsibility |
|------|--------|----------------|
| `MacTouchSettings` | `MacTouchCore` | Codable settings: tuned fields + `version` + `calibratedAt`. Applied onto `TapDetectorConfig` / `GestureRecognizerConfig`. |
| `CalibrationStage` | `MacTouchCore` | `.idle`, `.singles`, `.doubles`, `.done` (or equivalent) |
| `CalibrationSession` | `MacTouchCore` | Stage machine; collects idle samples and tap events; knows when a stage has enough data; exposes user-facing prompt text / progress |
| `CalibrationAnalyzer` | `MacTouchCore` | Pure functions: idle stats + single peaks + double gaps → `MacTouchSettings` |
| `CalibrationService` | `MacTouchCore` | Façade: feed `SensorSample`s (or processed path), return stage updates and final result |
| CLI wiring | `MacTouchProbe` | `--calibrate`, `--config-out`, `--config` |

Reuse existing `SignalProcessor` and `TapDetector`. Do **not** reimplement peak hunting outside `TapDetector`.

## Stage protocol

### 1. Idle (~3–5 seconds)

- Prompt: keep still; do not tap.
- Collect filtered-magnitude samples after a short warm-up.
- Compute quiet-noise statistics (at least mean and p95).
- Advance automatically when the idle duration elapses.

### 2. Singles

- Prompt: tap once, pause ~1 s, repeat.
- Require **≥ 5** accepted taps whose gaps from the previous tap are **> ~0.5 s** (so doubles are not counted as two singles).
- Record peak strengths (and timestamps) for those taps.
- Advance when the count is met (or allow a max duration / abort with error if under-collected).

### 3. Doubles

- Prompt: double-tap (~0.15 s apart), then pause before the next pair.
- Require **≥ 5** pairs.
- Pair consecutive taps whose gap is in **~0.05–0.35 s**; record those inter-tap gaps.
- Advance when enough pairs are collected.

### 4. Analyze → report → write

- Run `CalibrationAnalyzer`.
- Print recommended values and suggested CLI flags.
- Write JSON to `--config-out` (default `~/.config/MacTouch/settings.json`), creating parent directories as needed.

## Recommendation rules

| Setting | Rule |
|---------|------|
| `minAbsoluteThresholdG` | Between idle p95 and median single-tap peak (e.g. `idle_p95 * 1.5`, clamped below ~`0.6 * median_single_peak`) |
| `groupingWindow` | `clamp(median_double_gap * 1.8, 0.22, 0.45)` — e.g. 0.15 s → ~0.27 s |
| `gestureCooldown` | `clamp(groupingWindow * 0.6, 0.12, 0.30)` |
| Other tap/gesture knobs | Keep existing production defaults unless calibration clearly requires otherwise |

**Calibrate-time detector:** use a temporarily lower `minAbsoluteThresholdG` / confidence floor so light taps are not missed while collecting. Recommendations still target production-ready settings derived from measured peaks and gaps.

## Settings file

### JSON shape (v1)

```json
{
  "version": 1,
  "minAbsoluteThresholdG": 0.025,
  "groupingWindow": 0.27,
  "gestureCooldown": 0.16,
  "calibratedAt": "2026-08-16T21:00:00Z"
}
```

Only fields tuned in Phase 6. Additional fields may be added later with version bumps.

### Application

- `MacTouchSettings.apply(to: inout TapDetectorConfig)` sets threshold-related fields.
- `MacTouchSettings.apply(to: inout GestureRecognizerConfig)` sets `groupingWindow` and `cooldown`.
- Unknown or unsupported `version` → clear error; do not silently ignore.

## CLI

```bash
swift run MacTouchProbe --calibrate
swift run MacTouchProbe --calibrate --config-out ~/.config/MacTouch/settings.json
swift run MacTouchProbe --gestures --config ~/.config/MacTouch/settings.json
swift run MacTouchProbe --detect --config ~/.config/MacTouch/settings.json
```

- `--calibrate` opens the sensor, runs the wizard (process + detect under the hood), prints results, then writes JSON to `--config-out` (or the default path).
- Default `--config-out`: `~/.config/MacTouch/settings.json`.
- `--config <path>` loads settings for `--detect` and `--gestures`.
- No `--no-write` in Phase 6: always persist on successful calibration (print + file).

Suggested exit codes (extend existing table as needed):

| Code | Meaning |
|------|---------|
| existing 0–6 | Unchanged |
| 7 | Calibration incomplete (too few samples / taps) |
| 8 | Failed to write or read settings JSON |

## Error handling

- Sensor open / device missing: same behavior as existing probe modes.
- Too few singles or doubles: do **not** write settings; print what was collected and how to retry; exit non-zero (7).
- JSON I/O failure: exit non-zero (8) with path and underlying error.
- Privilege policy unchanged: non-root first.

## Testing

Unit tests only for Phase 6 core logic (no HID required):

1. **`CalibrationAnalyzer`** — synthetic idle stats + peaks + ~0.15 s gaps → expected grouping ≈ 0.27 s and sensible threshold/cooldown.
2. **`CalibrationSession`** — stage transitions and “enough samples” gates (idle timer, single gaps, double pairing).
3. **`MacTouchSettings`** — encode/decode round-trip; apply to configs.
4. **CLI option parsing** — `--calibrate`, `--config`, `--config-out` recognized (lightweight).

## File layout (expected)

```text
Sources/MacTouchCore/Settings/MacTouchSettings.swift
Sources/MacTouchCore/Calibration/CalibrationStage.swift
Sources/MacTouchCore/Calibration/CalibrationSession.swift
Sources/MacTouchCore/Calibration/CalibrationAnalyzer.swift
Sources/MacTouchCore/Calibration/CalibrationService.swift
Tests/MacTouchCoreTests/CalibrationAnalyzerTests.swift
Tests/MacTouchCoreTests/CalibrationSessionTests.swift
Tests/MacTouchCoreTests/MacTouchSettingsTests.swift
Sources/MacTouchProbe/MacTouchProbe.swift   # CLI wiring
README.md / handover.md                     # Phase 6 docs
```

Exact filenames may vary slightly; keep Calibration types cohesive under one folder.

## Success criteria

- `swift test` passes with new calibration/settings tests.
- Live `--calibrate` completes idle → singles → doubles on the development Mac without root.
- Written JSON loads via `--gestures --config …` and uses recommended grouping for ~0.15 s doubles.
- Handover/README updated to mark Phase 6 done and note Phase 7 next.

## Follow-ups (later phases)

- Phase 7: SwiftUI wizard + UserDefaults backed by the same `MacTouchSettings`.
- Optional: typing/trackpad stages; offline calibrate from recordings.

# MacTouch handover

Handoff document for continuing MacTouch development after Phases 1–5.

**Date:** 2026-08-16  
**Workspace:** `/Users/harsh/.cursor/MacTouch`  
**Dev machine used:** MacBook Pro 14" (Mac16,8), Apple M4 Pro, macOS 26.5.2, arm64  
**Sensor:** `AppleSPUHIDDevice` accel present (`PrimaryUsagePage=0xFF00`, `PrimaryUsage=3`, 22-byte reports)

---

## What this project is

Native macOS Swift tools that detect **physical taps/knocks on the aluminum chassis** using the internal Apple Silicon accelerometer (`AppleSPUHIDDevice` / SPU IMU). This is **not** touchscreen input.

Design goals (from the original brief):

- Swift + SwiftUI eventually
- IOKit HID in-process (no shelling out per sample)
- Local-only processing (no network)
- Clear separation: sensor → signal → tap detect → gestures → calibration → UI → actions

---

## Current status (Phases 1–5 complete)

| Phase | Status | Deliverable |
|-------|--------|-------------|
| 1 Sensor probe | Done | Live X/Y/Z CLI (`MacTouchProbe`) |
| 2 Record/replay | Done | CSV/JSON sessions + offline replay |
| 3 Signal processing | Done | Gravity remove, HP/LP, noise floor |
| 4 Tap detection | Done | Peak/decay/debounce/confidence |
| 5 Gestures | Done | Single / double / triple grouping |
| 6 Calibration | **Not started** | Recommended thresholds from live samples |
| 7 SwiftUI menu bar | **Not started** | Waveform, settings, counters, test mode |
| 8 Actions | **Not started** | Mute, Shortcuts, launch app, notify |

**Tests:** `swift test` — 33 tests passing (as of this handover).

**Privilege policy:** Non-root first. On the development Mac, HID open + streaming worked as a normal user (euid 501). Do not add `sudo` unless open/stream fails and you document why.

---

## Repository layout

```text
Package.swift
README.md
THIRD_PARTY_NOTICES.md
handover.md                 ← this file
Sources/MacTouchCore/
  Sensor/                   SensorSample, IMUReportParser, SensorService,
                            SensorRecording, SensorReplayer
  Signal/                   SignalProcessor (+ filters)
  Detection/                TapDetector, GestureRecognizer
Sources/MacTouchProbe/      CLI entry point
Tests/MacTouchCoreTests/
Fixtures/recordings/        Scrubbed fixtures only (after privacy review)
Recordings/                 Local captures (gitignored) — do not commit raw sessions blindly
```

---

## How to build and run

```bash
cd /path/to/MacTouch
swift build
swift test
swift run MacTouchProbe --help
```

Useful commands:

```bash
# Live probe
swift run MacTouchProbe --duration 5 --every 40

# Record / replay
swift run MacTouchProbe --record Recordings/session.csv --duration 6 --notes "light taps"
swift run MacTouchProbe --replay Recordings/session.csv --every 50

# Filtered preview
swift run MacTouchProbe --process --duration 5 --every 40

# Tap events
swift run MacTouchProbe --detect --duration 10 --every 100

# Gestures (single/double/triple)
swift run MacTouchProbe --gestures --duration 12 --every 100
swift run MacTouchProbe --gestures --grouping 0.28 --gesture-cooldown 0.20
```

Light taps on palm rest / lid edge only. Do not strike the display.

---

## Known issues / open problems

### 1. Single vs double gesture confusion (active)

Users report trouble distinguishing **single** and **double** taps.

**Cause:** Phase 5 grouping window tradeoff + real tap spacing.

- Default `--grouping 0.40` merges taps closer than 400 ms into one multi-tap gesture.
- Three taps ~120 ms apart in a recording became one **triple**.
- Singles are intentionally delayed by the grouping window so a second tap can still arrive.

**What Phase 6 (calibration) will help with:**

- Measure the user’s inter-tap intervals
- Recommend a better `groupingWindow`, threshold, and cooldown

**What Phase 6 will not magically remove:**

- The need to wait before finalizing a single
- 100% accuracy for every tap style

**Manual workaround until Phase 6:**

```bash
# Tighter grouping if separate singles are being merged
swift run MacTouchProbe --gestures --grouping 0.28 --gesture-cooldown 0.20

# Looser if intentional doubles are being split
swift run MacTouchProbe --gestures --grouping 0.45 --gesture-cooldown 0.20
```

Ask the user to pause ~0.5 s after a single before the next gesture.

### 2. Tap detector sensitivity (mostly fixed)

Early Phase 4 defaults were too aggressive for light chassis taps. Fixed by:

- Tuning thresholds from `Recordings/taps.csv` (filt peaks ≈ 0.05–0.07 g)
- Not including the tap itself in sustained-motion rejection
- Excluding the rising-edge tail from the pre-impact quiet check

If detection regresses on another Mac model, re-tune with a short `--record` + analysis before changing defaults globally.

### 3. Undocumented Apple API risk

`AppleSPUHIDDevice` is undocumented. May break on macOS updates. Preserve fallbacks and clear error messages.

### 4. Local recordings

`Recordings/` is gitignored. Inspect for private notes before promoting anything into `Fixtures/recordings/`.

---

## Recommended next work (Phase 6+)

1. **Phase 6 — CalibrationService**
   - Guided capture: idle, typing, trackpad, intentional taps
   - Recommend `detectionThreshold` / grouping / cooldown
   - Persist settings (later `AppSettings` / UserDefaults)

2. **Phase 7 — SwiftUI menu-bar app**
   - Start/stop, waveform, sensor status
   - Sensitivity / threshold / grouping / cooldown controls
   - Calibration wizard UI
   - Single/double/triple counters + debug event log
   - Test mode (no system actions)

3. **Phase 8 — Actions** (only after detection is reliable)
   - Mute, Shortcuts, launch app, notification
   - Explicit confirmation before arbitrary shell

Keep CLI (`MacTouchProbe`) working for offline regression while the UI grows.

---

## Architecture cheat sheet

```text
SensorService (IOKit HID)
    → SensorSample
        → SignalProcessor → ProcessedSample
            → TapDetector → TapEvent
                → GestureRecognizer → TapGestureEvent (single/double/triple)
```

Replay path: `SensorRecordingIO` / `SensorReplayer` feeds the same pipeline without HID.

---

## Research references (do not copy blindly)

Studied MIT-licensed / community projects — see `THIRD_PARTY_NOTICES.md`:

- olvvier/apple-silicon-accelerometer
- taigrr/apple-silicon-accelerometer, taigrr/spank
- shaircast/nocnoc
- AbdullahFID/MacSlapApp
- sinhong2011/slap-your-openclaw
- dinakars777/moody

Hardware constants (community-documented):

- Vendor page `0xFF00`, accel usage `3`, gyro usage `9`
- 22-byte reports, XYZ int32 LE at offset 6, scale `/65536` (Q16)
- Wake `AppleSPUHIDDriver`: ReportingState / PowerState / ReportInterval

---

## Agent / contributor notes

- Work **one phase at a time**; stop for user verification.
- Prefer non-root; explain before any elevation.
- Do not claim touch location / top-vs-side unless proven.
- Unit-test signal math and gesture timing; use recordings for replay tests.
- Preserve third-party attribution.

When resuming: read this file + `README.md`, run `swift test`, then start **Phase 6** unless the user redirects.

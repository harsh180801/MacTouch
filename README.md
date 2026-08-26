# MacTouch

MacTouch is a native macOS project that detects **physical taps/knocks on an Apple Silicon MacBook chassis** using the internal accelerometer (`AppleSPUHIDDevice`).  
This is **not** touchscreen input.

The repo currently ships as **source-only** (build and run locally).

## Compatibility

| Requirement | Notes |
|-------------|--------|
| Apple Silicon MacBook | MacBook Pro / Air with SPU IMU |
| `AppleSPUHIDDevice` | Usage page `0xFF00`, usage `3`, 22-byte reports |
| macOS 14+ | Built and tested against modern macOS |
| Not expected | Intel Macs, many desktops (for example Studio), devices without SPU IMU |

Development machine reference: MacBook Pro 14" (Mac16,8), Apple M4 Pro.

## Quick start (2 minutes)

```bash
git clone https://github.com/harsh180801/MacTouch.git
cd MacTouch
swift test
swift build
swift run MacTouchApp
```

If macOS prompts for permissions, allow Input Monitoring for the terminal/app host.

## Menu bar app (recommended)

Run:

```bash
swift run MacTouchApp
```

The popover includes:

- start/stop listening
- single/double/triple counters
- threshold/grouping/cooldown sliders
- in-app **Calibrate...**
- gesture action mapping (shortcut/mute/launch app/notify)

Settings path: `~/.config/MacTouch/settings.json`.

## Build and test

Requires Xcode or Command Line Tools with Swift 6.

```bash
cd /path/to/MacTouch
swift build
swift test
swift run MacTouchApp          # menu bar UI
swift run MacTouchProbe --help # CLI
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Samples received / replay finished |
| 1 | Open failed |
| 2 | Device not found |
| 3 | Opened but zero samples / empty recording |
| 4 | Failed to write recording |
| 5 | Failed to read recording |
| 6 | Realtime replay timed out |
| 7 | Calibration incomplete / analyzer rejected samples |
| 8 | Failed to load or save calibrated settings |
| 64 | Invalid CLI usage |

## Project layout

```text
Sources/MacTouchCore/Sensor/      HID access, recording, replay
Sources/MacTouchCore/Signal/      Magnitude, filters, SignalProcessor
Sources/MacTouchCore/Detection/   TapDetector, GestureRecognizer
Sources/MacTouchCore/Calibration/ CalibrationService, CalibrationSession, CalibrationAnalyzer
Sources/MacTouchCore/Settings/    MacTouchSettings, SettingsStore (JSON)
Sources/MacTouchProbe/            CLI (live / record / replay / process / detect / gestures / calibrate)
Sources/MacTouchApp/              SwiftUI menu-bar app
Tests/MacTouchCoreTests/          Unit tests
docs/design/                      Design docs
Fixtures/recordings/              Scrubbed fixtures only
Recordings/                       Local captures (gitignored)
```

## Privilege policy

1. Discover device without elevation (`ioreg` / IOKit matching).
2. Attempt open/stream as the current user first.
3. If open succeeds but no samples arrive, check Input Monitoring.
4. Do **not** automatically use `sudo`.

## Troubleshooting

**Device not found**  
Verify Apple Silicon MacBook and `ioreg -c AppleSPUHIDDevice` reports usage page `65280` (`0xFF00`) and usage `3`.

**Open failed**  
Grant Input Monitoring to Terminal/Cursor and retry as non-root.

**Zero samples**  
Capture exact stderr output first; do not jump to privileged helpers.

## Related docs

- Website: `docs/site/`
- Menu bar app design: [docs/design/2026-08-17-menubar-app.md](docs/design/2026-08-17-menubar-app.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## License / attribution

MacTouch original code: see repository license when added.

Hardware access/report-layout understanding was informed by community projects; implementation here is original. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

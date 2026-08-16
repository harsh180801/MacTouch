# MacTouch

Native macOS tools that detect **physical taps/knocks on a MacBook aluminum chassis** using the internal Apple Silicon accelerometer (`AppleSPUHIDDevice`). This is **not** touchscreen input.

## Status

- **Phase 1:** CLI sensor probe that prints live X/Y/Z acceleration.
- **Phase 2:** Record sessions to CSV/JSON and replay them offline (no HID / no elevation).
- **Phase 3:** Signal processing — gravity removal, impact band filter, rolling noise baseline.
- **Phase 4:** Tap detection — peak/decay, debounce, confidence, typing/motion rejection.
- **Phase 5:** Gesture recognition — single / double / triple tap grouping.

Later phases add calibration and a SwiftUI menu-bar app.

## Compatibility

| Requirement | Notes |
|-------------|--------|
| Apple Silicon MacBook | MacBook Pro / Air with SPU IMU |
| `AppleSPUHIDDevice` | Accel: usage page `0xFF00`, usage `3`, 22-byte reports |
| macOS 14+ | Built and tested against newer macOS as available |
| Not expected | Intel Macs, many desktops (e.g. Studio), machines without SPU IMU |

On this project’s development machine: MacBook Pro 14" (Mac16,8), Apple M4 Pro.

## Privilege policy

1. **Discover** the device without elevation (`ioreg` / IOKit matching).
2. **Open and stream as the current user** first.
3. If open succeeds but no samples arrive, check **Input Monitoring** for the terminal/host app.
4. **Do not use `sudo` automatically.** Elevation is only considered after a clear failure explanation.

## Build

Requires Xcode or Command Line Tools with Swift 6.

```bash
cd /path/to/MacTouch
swift build
swift test
```

## Phase 1 — sensor probe

```bash
swift run MacTouchProbe
swift run MacTouchProbe --duration 10 --every 40
```

Light taps on the chassis are enough. **Do not hit the display hard.**

Example line:

```text
t=123.456789  x=+0.01234  y=-0.02345  z=+0.99876  mag=0.99912
```

At rest, magnitude is typically near **1 g** (gravity).

## Phase 2 — record and replay

Record a short live session (creates `Recordings/` locally; gitignored):

```bash
mkdir -p Recordings
swift run MacTouchProbe --record Recordings/session.csv --duration 5 --every 50 --notes "idle then light palm taps"
```

Also supports `.json`. Timestamps in the file are **relative** (first sample ≈ `0`), so fixtures do not store host uptime.

Replay without opening the accelerometer:

```bash
swift run MacTouchProbe --replay Recordings/session.csv --every 50
swift run MacTouchProbe --replay Recordings/session.csv --realtime --every 50
```

| Flag | Meaning |
|------|---------|
| `--record <path>` | After live capture, write `.csv` or `.json` |
| `--replay <path>` | Offline playback (no HID) |
| `--realtime` | Pace replay using recorded timestamp gaps |
| `--notes <text>` | Metadata stored in the recording |
| `--duration <sec>` | Live capture length (default `8`) |
| `--every <n>` | Print 1 of every *n* samples |
| `--process` | Print filtered preview: raw / linear / filt / floor / norm |
| `--detect` | Run tap detector and print `TAP` events |

**Privacy:** Inspect recordings before committing anything under `Fixtures/`. Prefer relative timestamps and short notes; avoid personal filenames or unrelated metadata.

## Phase 3 — signal processing

`SignalProcessor` turns raw g-force samples into impact-oriented features:

1. **Raw magnitude** — √(x²+y²+z²) (≈1 at rest because of gravity)
2. **Gravity removal** — slow EMA low-pass estimates gravity; subtract to get linear accel
3. **Impact filter** — first-order high-pass (~10 Hz) plus optional low-pass (~80 Hz) on the linear vector
4. **Noise floor** — rolling baseline of filtered magnitude (frozen while elevated)
5. **Normalized excess** — how many noise-deviation units the signal sits above the floor

Defaults are documented in `SignalProcessorConfig` (sample rate, time constants, cutoffs). They are starting points, not magic hardware constants.

Preview on live or replayed data:

```bash
swift run MacTouchProbe --process --duration 5 --every 40
swift run MacTouchProbe --replay Recordings/session.csv --process --every 40
```

Example processed line:

```text
t=0.500000  raw=0.98500  lin=0.01200  filt=0.00800  floor=0.00600  norm=0.40
```

A light chassis tap should briefly raise `filt` and `norm` while `raw` stays near 1g.

## Phase 4 — tap detection

`TapDetector` consumes `ProcessedSample` frames and emits `TapEvent`s for individual impacts (not yet single/double/triple gestures).

Defaults were tuned from a real light-tap capture on this MacBook (`filt` peaks ≈ 0.05–0.07 g):

- rapid rise above an adaptive threshold, then decay
- amplitude + jerk *or* a moderately hard linear hit
- sustained-motion checks use the **pre-impact** window only (so the tap itself is not rejected)
- debounce + confidence score

```bash
swift run MacTouchProbe --detect --duration 8 --every 100
swift run MacTouchProbe --replay Recordings/taps.csv --detect
```

Example:

```text
TAP t=1.204  peak=0.0621  lin=0.0850  jerk=12.3  dur=0.028  conf=0.55  [impulse,jerk]
```

## Phase 5 — gesture recognition

`GestureRecognizer` groups `TapEvent`s into **single / double / triple** using a configurable silence window.

**Timing tradeoff:** a lone tap is not finalized until `--grouping` seconds of quiet pass (default 0.40s). That delay is required to see whether another tap is coming. Shorter window ⇒ snappier singles, more mis-grouped doubles. Longer window ⇒ reliable multi-taps, laggy singles.

```bash
swift run MacTouchProbe --gestures --duration 12 --every 100
swift run MacTouchProbe --replay Recordings/taps.csv --gestures
swift run MacTouchProbe --gestures --grouping 0.35 --gesture-cooldown 0.25
```

Example:

```text
GESTURE single  taps=1  t=1.204  final=1.604  peak=0.0621  conf=0.55
GESTURE double  taps=2  t=2.100  final=2.520  peak=0.0710  conf=0.61
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Samples received / replay finished |
| 1 | Open failed |
| 2 | Device not found |
| 3 | Opened but zero samples / empty recording |
| 4 | Failed to write recording |
| 5 | Failed to read recording |
| 6 | Realtime replay timed out |

## Project layout

```text
Sources/MacTouchCore/Sensor/      HID access, recording, replay
Sources/MacTouchCore/Signal/      Magnitude, filters, SignalProcessor
Sources/MacTouchCore/Detection/   TapDetector, GestureRecognizer
Sources/MacTouchProbe/            CLI (live / record / replay / process / detect / gestures)
Tests/MacTouchCoreTests/          Unit tests
Fixtures/recordings/             Scrubbed fixtures only (after privacy review)
Recordings/                       Local captures (gitignored)
```

## Troubleshooting

**Device not found**  
Confirm Apple Silicon MacBook and `ioreg -c AppleSPUHIDDevice` shows usage page `65280` (`0xFF00`) and usage `3`.

**Open failed**  
Grant Input Monitoring to Terminal/Cursor if macOS prompts. Re-run without sudo.

**Zero samples**  
Driver may not be streaming. Note the exact stderr output before considering any privileged helper.

## License / attribution

MacTouch original code: see repository license when added.

Hardware access and report layout were documented by community projects (ideas reimplemented; not copied wholesale). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

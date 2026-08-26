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


## License / attribution

MacTouch original code: see repository license when added.

Hardware access/report-layout understanding was informed by community projects; implementation here is original. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

# Third-party notices

MacTouch reimplements sensor access and detection ideas after studying community projects.
It does **not** vendor their source trees. Preserve these notices when redistributing.

## Studied projects (MIT unless noted in their repos)

| Project | Role in research |
|---------|------------------|
| [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) | AppleSPUHIDDevice discovery, 22-byte Q16 report layout, driver wake properties |
| [taigrr/apple-silicon-accelerometer](https://github.com/taigrr/apple-silicon-accelerometer) | Go port of the same HID path and vibration detector ideas |
| [taigrr/spank](https://github.com/taigrr/spank) | Impact amplitude / cooldown UX patterns |
| [shaircast/nocnoc](https://github.com/shaircast/nocnoc) | Swift IOKit HID streaming and knock grouping concepts |
| [AbdullahFID/MacSlapApp](https://github.com/AbdullahFID/MacSlapApp) | Driver-wake-after-open notes; amp+jerk typing rejection ideas |
| [sinhong2011/slap-your-openclaw](https://github.com/sinhong2011/slap-your-openclaw) | Device auto-lock / anti-false-positive measures |
| [dinakars777/moody](https://github.com/dinakars777/moody) | Compatibility framing for Apple Silicon MacBooks |

## Article

Olivier Bourbonnais — [Your macbook has an accelerometer…](https://medium.com/@oli.bourbonnais/your-macbook-has-an-accelerometer-and-you-can-read-it-in-real-time-in-python-28d9395fb180)

## Hardware constants (community-documented)

- HID vendor page `0xFF00`, accelerometer usage `3`, gyroscope usage `9`
- IMU report length `22`, XYZ `int32` LE at offset `6`, scale `65536` (Q16)
- Driver properties: `SensorPropertyReportingState`, `SensorPropertyPowerState`, `ReportInterval`

These interfaces are **undocumented by Apple** and may change.

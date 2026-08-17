# Phase 6 Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live guided calibration wizard that recommends and persists `minAbsoluteThresholdG`, `groupingWindow`, and `gestureCooldown` via a shared `MacTouchSettings` JSON model and CLI flags.

**Architecture:** Reuse `SignalProcessor` + `TapDetector` (with a temporarily sensitive config) inside `CalibrationService`. `CalibrationSession` collects idle magnitudes and tap events across idle → singles → doubles; `CalibrationAnalyzer` turns those stats into `MacTouchSettings`. CLI `--calibrate` runs the wizard and writes JSON; `--config` loads settings into detect/gestures modes.

**Tech Stack:** Swift 6 / SwiftPM, macOS 14+, Foundation `Codable` JSON, Swift Testing (`import Testing`), existing IOKit HID path (live only).

**Spec:** `docs/superpowers/specs/2026-08-16-calibration-design.md`

## Global Constraints

- Non-root first for live HID; same privilege policy as Phases 1–5.
- Do not invent a second peak detector — feed `TapDetector` events into the session.
- Live wizard only (no replay calibrate).
- Always write JSON on successful calibration (no `--no-write`).
- Default config path: `~/.config/MacTouch/settings.json`.
- Exit code 7 = incomplete calibration; 8 = settings JSON I/O failure.
- Stages: idle → singles (≥5 isolated taps) → doubles (≥5 pairs); then analyze.
- Recommendation formulas from the spec (grouping ≈ median_gap × 1.8, clamped).
- Keep files focused under `Sources/MacTouchCore/Settings/` and `…/Calibration/`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `Sources/MacTouchCore/Settings/MacTouchSettings.swift` | Codable settings v1; apply to tap/gesture configs; load/save JSON |
| `Sources/MacTouchCore/Calibration/CalibrationTypes.swift` | `CalibrationStage`, progress/result types, collection config constants |
| `Sources/MacTouchCore/Calibration/CalibrationAnalyzer.swift` | Pure recommendation math from collected stats |
| `Sources/MacTouchCore/Calibration/CalibrationSession.swift` | Stage machine + collection gates |
| `Sources/MacTouchCore/Calibration/CalibrationService.swift` | Façade: processor + sensitive detector + session |
| `Tests/MacTouchCoreTests/MacTouchSettingsTests.swift` | Round-trip + apply + load/save |
| `Tests/MacTouchCoreTests/CalibrationAnalyzerTests.swift` | Formula tests (~0.15 s → ~0.27 s) |
| `Tests/MacTouchCoreTests/CalibrationSessionTests.swift` | Stage transitions / pairing |
| `Sources/MacTouchProbe/MacTouchProbe.swift` | `--calibrate`, `--config`, `--config-out`; wizard loop |
| `Sources/MacTouchProbe/ProbeArgumentParser.swift` | Extracted flag parsing (testable) |
| `Tests/MacTouchCoreTests/ProbeArgumentParserTests.swift` | Parse calibrate/config flags |
| `README.md`, `handover.md` | Phase 6 docs |

Note: `ProbeArgumentParser` lives in the executable target. SwiftPM cannot easily unit-test executable-only code from `MacTouchCoreTests`. Put parser helpers that are pure (path resolution, settings application from flags) in **MacTouchCore** where possible; for CLI flag parsing, either (a) move `ProbeArgumentParser` into MacTouchCore as `MacTouchProbeOptions`, or (b) keep parsing in the executable and cover it with a manual checklist only. **This plan uses (a):** `MacTouchProbeOptions` + `MacTouchProbeOptions.parse(_:)` in MacTouchCore so tests stay in `MacTouchCoreTests`.

---

### Task 1: `MacTouchSettings` model + apply + JSON I/O

**Files:**
- Create: `Sources/MacTouchCore/Settings/MacTouchSettings.swift`
- Test: `Tests/MacTouchCoreTests/MacTouchSettingsTests.swift`

**Interfaces:**
- Consumes: `TapDetectorConfig`, `GestureRecognizerConfig`
- Produces:
  - `public struct MacTouchSettings: Codable, Equatable, Sendable`
  - `public static let currentVersion = 1`
  - `public func apply(to config: inout TapDetectorConfig)`
  - `public func apply(to config: inout GestureRecognizerConfig)`
  - `public static func load(from url: URL) throws -> MacTouchSettings`
  - `public func save(to url: URL) throws`
  - `public enum MacTouchSettingsError: Error` with `.unsupportedVersion(Int)`, `.encodeFailed`, `.decodeFailed`, `.ioFailed(String)`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import MacTouchCore

struct MacTouchSettingsTests {
    @Test func roundTripJSONPreservesFields() throws {
        let original = MacTouchSettings(
            version: 1,
            minAbsoluteThresholdG: 0.025,
            groupingWindow: 0.27,
            gestureCooldown: 0.16,
            calibratedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MacTouchSettings.self, from: data)
        #expect(decoded == original)
    }

    @Test func applyUpdatesTapAndGestureConfigs() {
        var tap = TapDetectorConfig()
        var gesture = GestureRecognizerConfig()
        let settings = MacTouchSettings(
            version: 1,
            minAbsoluteThresholdG: 0.031,
            groupingWindow: 0.28,
            gestureCooldown: 0.17,
            calibratedAt: Date()
        )
        settings.apply(to: &tap)
        settings.apply(to: &gesture)
        #expect(tap.minAbsoluteThresholdG == 0.031)
        #expect(gesture.groupingWindow == 0.28)
        #expect(gesture.cooldown == 0.17)
    }

    @Test func loadRejectsUnsupportedVersion() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-bad-version-\(UUID().uuidString).json")
        try Data(#"{ "version": 99, "minAbsoluteThresholdG": 0.02, "groupingWindow": 0.4, "gestureCooldown": 0.2, "calibratedAt": 0 }"#.utf8)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MacTouchSettingsError.self) {
            _ = try MacTouchSettings.load(from: url)
        }
    }

    @Test func saveCreatesParentDirectories() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-cfg-\(UUID().uuidString)/nested")
        let url = dir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let settings = MacTouchSettings(
            version: 1,
            minAbsoluteThresholdG: 0.02,
            groupingWindow: 0.40,
            gestureCooldown: 0.20,
            calibratedAt: Date()
        )
        try settings.save(to: url)
        let loaded = try MacTouchSettings.load(from: url)
        #expect(loaded.minAbsoluteThresholdG == 0.02)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MacTouchSettingsTests`
Expected: FAIL (type `MacTouchSettings` not found)

- [ ] **Step 3: Implement `MacTouchSettings`**

```swift
import Foundation

public enum MacTouchSettingsError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case encodeFailed
    case decodeFailed
    case ioFailed(String)
}

public struct MacTouchSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var minAbsoluteThresholdG: Double
    public var groupingWindow: TimeInterval
    public var gestureCooldown: TimeInterval
    public var calibratedAt: Date

    public init(
        version: Int = currentVersion,
        minAbsoluteThresholdG: Double,
        groupingWindow: TimeInterval,
        gestureCooldown: TimeInterval,
        calibratedAt: Date = Date()
    ) {
        self.version = version
        self.minAbsoluteThresholdG = minAbsoluteThresholdG
        self.groupingWindow = groupingWindow
        self.gestureCooldown = gestureCooldown
        self.calibratedAt = calibratedAt
    }

    public func apply(to config: inout TapDetectorConfig) {
        config.minAbsoluteThresholdG = minAbsoluteThresholdG
    }

    public func apply(to config: inout GestureRecognizerConfig) {
        config.groupingWindow = groupingWindow
        config.cooldown = gestureCooldown
    }

    public static func load(from url: URL) throws -> MacTouchSettings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MacTouchSettingsError.ioFailed(error.localizedDescription)
        }
        let settings: MacTouchSettings
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            settings = try decoder.decode(MacTouchSettings.self, from: data)
        } catch {
            throw MacTouchSettingsError.decodeFailed
        }
        guard settings.version == currentVersion else {
            throw MacTouchSettingsError.unsupportedVersion(settings.version)
        }
        return settings
    }

    public func save(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw MacTouchSettingsError.ioFailed(error.localizedDescription)
        }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(self)
        } catch {
            throw MacTouchSettingsError.encodeFailed
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MacTouchSettingsError.ioFailed(error.localizedDescription)
        }
    }

    /// Default on-disk location for calibrated settings.
    public static var defaultConfigURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("MacTouch")
            .appendingPathComponent("settings.json")
    }
}
```

Use ISO-8601 dates so the JSON matches the spec’s string timestamps. For the unsupported-version fixture, encode `calibratedAt` as an ISO-8601 string (or decode with a flexible strategy). Prefer writing the bad fixture via `JSONSerialization` / string with `"calibratedAt":"2020-01-01T00:00:00Z"`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MacTouchSettingsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacTouchCore/Settings/MacTouchSettings.swift Tests/MacTouchCoreTests/MacTouchSettingsTests.swift
git commit -m "$(cat <<'EOF'
Add MacTouchSettings Codable model with JSON load/save.

Shared settings shape for Phase 6 calibration and future Phase 7 UserDefaults.
EOF
)"
```

---

### Task 2: `CalibrationAnalyzer` recommendation math

**Files:**
- Create: `Sources/MacTouchCore/Calibration/CalibrationTypes.swift` (stats input types only if needed here; otherwise keep in Analyzer file)
- Create: `Sources/MacTouchCore/Calibration/CalibrationAnalyzer.swift`
- Test: `Tests/MacTouchCoreTests/CalibrationAnalyzerTests.swift`

**Interfaces:**
- Consumes: none from Task 1 except `MacTouchSettings`
- Produces:
  - `public struct CalibrationStats: Equatable, Sendable` with `idleP95`, `singlePeaks: [Double]`, `doubleGaps: [TimeInterval]`
  - `public enum CalibrationAnalyzer`
  - `public static func recommend(from stats: CalibrationStats, now: Date = Date()) throws -> MacTouchSettings`
  - `public enum CalibrationAnalyzerError: Error` with `.insufficientSingles`, `.insufficientDoubles`, `.insufficientIdle`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import MacTouchCore

struct CalibrationAnalyzerTests {
    @Test func recommendsGroupingForFifteenHundredMsDoubles() throws {
        let stats = CalibrationStats(
            idleP95: 0.008,
            singlePeaks: [0.055, 0.060, 0.058, 0.062, 0.057],
            doubleGaps: [0.14, 0.15, 0.16, 0.15, 0.15]
        )
        let settings = try CalibrationAnalyzer.recommend(from: stats, now: Date(timeIntervalSince1970: 0))
        // median gap 0.15 * 1.8 = 0.27
        #expect(abs(settings.groupingWindow - 0.27) < 0.001)
        #expect(abs(settings.gestureCooldown - 0.162) < 0.001) // 0.27 * 0.6
        #expect(settings.version == 1)
        // threshold: idleP95 * 1.5 = 0.012, but clamp below 0.6 * median peak (~0.058)
        #expect(settings.minAbsoluteThresholdG > stats.idleP95)
        #expect(settings.minAbsoluteThresholdG < 0.6 * 0.058 + 0.001)
    }

    @Test func clampsGroupingWindowToBounds() throws {
        let low = CalibrationStats(
            idleP95: 0.005,
            singlePeaks: Array(repeating: 0.05, count: 5),
            doubleGaps: Array(repeating: 0.05, count: 5) // 0.05*1.8=0.09 → clamp 0.22
        )
        let high = CalibrationStats(
            idleP95: 0.005,
            singlePeaks: Array(repeating: 0.05, count: 5),
            doubleGaps: Array(repeating: 0.40, count: 5) // 0.72 → clamp 0.45
        )
        #expect(try CalibrationAnalyzer.recommend(from: low).groupingWindow == 0.22)
        #expect(try CalibrationAnalyzer.recommend(from: high).groupingWindow == 0.45)
    }

    @Test func throwsWhenTooFewDoubles() {
        let stats = CalibrationStats(
            idleP95: 0.008,
            singlePeaks: Array(repeating: 0.05, count: 5),
            doubleGaps: [0.15, 0.15] // < 5
        )
        #expect(throws: CalibrationAnalyzerError.insufficientDoubles) {
            _ = try CalibrationAnalyzer.recommend(from: stats)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalibrationAnalyzerTests`
Expected: FAIL (`CalibrationAnalyzer` missing)

- [ ] **Step 3: Implement analyzer**

```swift
import Foundation

public struct CalibrationStats: Equatable, Sendable {
    public var idleP95: Double
    public var singlePeaks: [Double]
    public var doubleGaps: [TimeInterval]

    public init(idleP95: Double, singlePeaks: [Double], doubleGaps: [TimeInterval]) {
        self.idleP95 = idleP95
        self.singlePeaks = singlePeaks
        self.doubleGaps = doubleGaps
    }
}

public enum CalibrationAnalyzerError: Error, Equatable, Sendable {
    case insufficientIdle
    case insufficientSingles
    case insufficientDoubles
}

public enum CalibrationAnalyzer {
    public static let minimumSingles = 5
    public static let minimumDoubles = 5

    public static func recommend(from stats: CalibrationStats, now: Date = Date()) throws -> MacTouchSettings {
        guard stats.idleP95.isFinite, stats.idleP95 >= 0 else {
            throw CalibrationAnalyzerError.insufficientIdle
        }
        guard stats.singlePeaks.count >= minimumSingles else {
            throw CalibrationAnalyzerError.insufficientSingles
        }
        guard stats.doubleGaps.count >= minimumDoubles else {
            throw CalibrationAnalyzerError.insufficientDoubles
        }

        let medianPeak = median(stats.singlePeaks)
        let proposedThreshold = stats.idleP95 * 1.5
        let upper = 0.6 * medianPeak
        let minAbsoluteThresholdG = min(max(proposedThreshold, 0.01), upper)

        let medianGap = median(stats.doubleGaps)
        let groupingWindow = clamp(medianGap * 1.8, 0.22, 0.45)
        let gestureCooldown = clamp(groupingWindow * 0.6, 0.12, 0.30)

        return MacTouchSettings(
            version: MacTouchSettings.currentVersion,
            minAbsoluteThresholdG: minAbsoluteThresholdG,
            groupingWindow: groupingWindow,
            gestureCooldown: gestureCooldown,
            calibratedAt: now
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(value, lo), hi)
    }
}
```

If `proposedThreshold > upper` (very quiet idle + soft taps), still use `upper` via `min(...)`. Ensure `upper` is at least a small floor (e.g. if median peak is tiny, `max(upper, 0.015)`). Document that choice in a one-line comment if added.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalibrationAnalyzerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacTouchCore/Calibration/CalibrationAnalyzer.swift Tests/MacTouchCoreTests/CalibrationAnalyzerTests.swift
git commit -m "$(cat <<'EOF'
Add CalibrationAnalyzer recommendation formulas.

Derive threshold, grouping, and cooldown from idle noise and tap timing stats.
EOF
)"
```

---

### Task 3: `CalibrationSession` stage machine

**Files:**
- Create: `Sources/MacTouchCore/Calibration/CalibrationTypes.swift`
- Create: `Sources/MacTouchCore/Calibration/CalibrationSession.swift`
- Test: `Tests/MacTouchCoreTests/CalibrationSessionTests.swift`

**Interfaces:**
- Consumes: `TapEvent`, `CalibrationStats`, `CalibrationAnalyzer`
- Produces:
  - `public enum CalibrationStage: String, Equatable, Sendable { case idle, singles, doubles, done }`
  - `public struct CalibrationProgress: Equatable, Sendable` — `stage`, `prompt`, `idleSamples`, `singleCount`, `doublePairCount`, `requiredSingles`, `requiredDoubles`
  - `public struct CalibrationSessionConfig: Equatable, Sendable` — idle duration, warm-up, min singles/doubles, single isolation gap, double gap range
  - `public final class CalibrationSession`
  - `func ingest(filteredMagnitude: Double, timestamp: TimeInterval)`
  - `func ingest(tap: TapEvent)`
  - `func poll(now: TimeInterval) -> CalibrationProgress`
  - `func makeStats() throws -> CalibrationStats` (only valid when stage == `.done`, or throws)
  - Defaults: idleDuration=4.0, idleWarmup=0.5, requiredSingles=5, requiredDoubles=5, singleMinGap=0.5, doubleGap=(0.05, 0.35)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import MacTouchCore

struct CalibrationSessionTests {
    private func tap(at t: TimeInterval, peak: Double = 0.06) -> TapEvent {
        TapEvent(
            timestamp: t,
            peakStrength: peak,
            peakLinearMagnitude: peak,
            peakJerk: 20,
            duration: 0.02,
            confidence: 0.5,
            reasons: ["test"]
        )
    }

    @Test func idleAdvancesAfterDuration() {
        let session = CalibrationSession(
            config: CalibrationSessionConfig(idleDurationSeconds: 1.0, idleWarmupSeconds: 0.2)
        )
        session.start(at: 0)
        // During warmup — magnitudes ignored for stats
        session.ingest(filteredMagnitude: 0.05, timestamp: 0.1)
        // After warmup — collect quiet samples
        for i in 0..<50 {
            session.ingest(filteredMagnitude: 0.008, timestamp: 0.3 + Double(i) * 0.01)
        }
        let mid = session.poll(now: 0.5)
        #expect(mid.stage == .idle)
        let after = session.poll(now: 1.05)
        #expect(after.stage == .singles)
    }

    @Test func singlesRequireIsolatedTaps() {
        let session = CalibrationSession(
            config: CalibrationSessionConfig(idleDurationSeconds: 0.1, idleWarmupSeconds: 0)
        )
        session.start(at: 0)
        _ = session.poll(now: 0.15) // → singles
        // Two taps 0.15s apart — second should NOT count as a new single
        session.ingest(tap: tap(at: 1.0, peak: 0.05))
        session.ingest(tap: tap(at: 1.15, peak: 0.05))
        #expect(session.poll(now: 1.2).singleCount == 1)
        session.ingest(tap: tap(at: 2.0, peak: 0.06))
        #expect(session.poll(now: 2.1).singleCount == 2)
    }

    @Test func doublesPairCloseGapsAndFinish() {
        var config = CalibrationSessionConfig(idleDurationSeconds: 0.05, idleWarmupSeconds: 0)
        config.requiredSingles = 2
        config.requiredDoubles = 2
        let session = CalibrationSession(config: config)
        session.start(at: 0)
        _ = session.poll(now: 0.1)
        // Complete singles quickly
        session.ingest(tap: tap(at: 1.0))
        session.ingest(tap: tap(at: 2.0))
        #expect(session.poll(now: 2.1).stage == .doubles)
        // Pair 1
        session.ingest(tap: tap(at: 3.0))
        session.ingest(tap: tap(at: 3.15))
        // Pair 2
        session.ingest(tap: tap(at: 4.5))
        session.ingest(tap: tap(at: 4.65))
        let done = session.poll(now: 4.7)
        #expect(done.stage == .done)
        #expect(done.doublePairCount == 2)
        let stats = try! session.makeStats()
        #expect(stats.doubleGaps.count == 2)
        #expect(abs(stats.doubleGaps[0] - 0.15) < 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalibrationSessionTests`
Expected: FAIL

- [ ] **Step 3: Implement session + types**

Implement stage machine:

1. `start(at:)` sets `stage = .idle`, records `stageStartedAt`.
2. Idle: after `idleWarmupSeconds`, append `filteredMagnitude` to idle buffer. When `now - start >= idleDurationSeconds`, compute `idleP95` (percentile), move to `.singles`.
3. Singles: on tap, if `tap.timestamp - lastAcceptedSingle >= singleMinGap` (or first), append peak; when count ≥ required, go `.doubles`. Clear any pending unpaired double candidate.
4. Doubles: keep `pendingTap`. On new tap, if gap in `[0.05, 0.35]`, record gap and clear pending; else replace pending with new tap (or clear if gap too large). When pairs ≥ required → `.done`.
5. `prompt` strings:
   - idle: `"Keep still — do not tap."`
   - singles: `"Tap once, pause ~1s, repeat (\(count)/\(required))."`
   - doubles: `"Double-tap (~0.15s apart), then pause (\(pairs)/\(required))."`
   - done: `"Calibration complete."`

Percentile helper: sort idle samples; index `Int(0.95 * (n-1))`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalibrationSessionTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacTouchCore/Calibration/CalibrationTypes.swift Sources/MacTouchCore/Calibration/CalibrationSession.swift Tests/MacTouchCoreTests/CalibrationSessionTests.swift
git commit -m "$(cat <<'EOF'
Add CalibrationSession stage machine for idle/singles/doubles.

Collect noise stats and tap timing with explicit progress prompts.
EOF
)"
```

---

### Task 4: `CalibrationService` façade

**Files:**
- Create: `Sources/MacTouchCore/Calibration/CalibrationService.swift`
- Modify: `Tests/MacTouchCoreTests/CalibrationSessionTests.swift` (add one integration-style test) **or** Create: `Tests/MacTouchCoreTests/CalibrationServiceTests.swift`

**Interfaces:**
- Consumes: `SensorSample`, `SignalProcessor`, `TapDetector`, `CalibrationSession`, `CalibrationAnalyzer`, `MacTouchSettings`
- Produces:
  - `public final class CalibrationService`
  - `public static func collectionTapConfig() -> TapDetectorConfig` — lower `minAbsoluteThresholdG` (e.g. `0.012`) and `minConfidence` (e.g. `0.15`) for collection only
  - `init(sessionConfig: CalibrationSessionConfig = .init())`
  - `func start(at timestamp: TimeInterval)`
  - `func ingest(_ sample: SensorSample) -> CalibrationProgress`
  - `func finish() throws -> MacTouchSettings` — requires `.done`; calls analyzer

- [ ] **Step 1: Write the failing test**

```swift
@Test func serviceReachesDoneFromSyntheticSamples() throws {
    // Build a short synthetic stream: idle quiet samples, then isolated singles, then doubles.
    // Use CalibrationService with a tiny idle duration; feed SensorSample values that
    // SignalProcessor can turn into detectable taps OR bypass by testing finish() after
    // manually driving session — prefer full ingest path with exaggerated spikes.
}
```

Practical approach for a reliable unit test without flaky detector tuning:

```swift
struct CalibrationServiceTests {
    @Test func collectionTapConfigIsMoreSensitiveThanDefaults() {
        let collection = CalibrationService.collectionTapConfig()
        let defaults = TapDetectorConfig()
        #expect(collection.minAbsoluteThresholdG < defaults.minAbsoluteThresholdG)
        #expect(collection.minConfidence <= defaults.minConfidence)
    }

    @Test func finishThrowsIfNotDone() {
        let service = CalibrationService(
            sessionConfig: CalibrationSessionConfig(idleDurationSeconds: 10, idleWarmupSeconds: 0)
        )
        service.start(at: 0)
        #expect(throws: CalibrationAnalyzerError.self) {
            _ = try service.finish()
        }
    }
}
```

Full pipeline tap synthesis is optional if detector thresholds make it brittle; session tests already cover staging. Service test focuses on wiring + sensitive config + `finish()` gate.

Also implement `finish()` as:

```swift
public func finish() throws -> MacTouchSettings {
    let stats = try session.makeStats()
    return try CalibrationAnalyzer.recommend(from: stats)
}
```

`ingest` runs `processor.process` → `session.ingest(filteredMagnitude:)` always; if `detector.process` returns a tap, `session.ingest(tap:)`; then `session.poll(now:)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalibrationServiceTests`
Expected: FAIL

- [ ] **Step 3: Implement `CalibrationService`**

Wire `SignalProcessor()`, `TapDetector(config: Self.collectionTapConfig())`, and `CalibrationSession`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalibrationServiceTests`
Expected: PASS  
Also: `swift test` (full suite still green)

- [ ] **Step 5: Commit**

```bash
git add Sources/MacTouchCore/Calibration/CalibrationService.swift Tests/MacTouchCoreTests/CalibrationServiceTests.swift
git commit -m "$(cat <<'EOF'
Add CalibrationService façade over signal, tap detect, and session.

Uses a more sensitive detector only while collecting calibration samples.
EOF
)"
```

---

### Task 5: Probe options parsing (`--calibrate` / `--config` / `--config-out`)

**Files:**
- Create: `Sources/MacTouchCore/Settings/MacTouchProbeOptions.swift`
- Test: `Tests/MacTouchCoreTests/MacTouchProbeOptionsTests.swift`
- Modify: `Sources/MacTouchProbe/MacTouchProbe.swift` (switch `main` to use parser — light touch now, full wizard in Task 6)

**Interfaces:**
- Produces:
  - `public struct MacTouchProbeOptions: Equatable, Sendable`
  - fields: existing probe fields + `calibrate: Bool`, `configURL: URL?`, `configOutURL: URL?`
  - `public static func parse(arguments: [String]) -> Result<MacTouchProbeOptions, MacTouchProbeOptionsError>`
  - Default `configOutURL` when `calibrate == true`: `MacTouchSettings.defaultConfigURL` (unless `--config-out` set)

- [ ] **Step 1: Write failing tests**

```swift
@Test func parsesCalibrateAndConfigOut() throws {
    let options = try MacTouchProbeOptions.parse(arguments: [
        "--calibrate", "--config-out", "/tmp/mactouch-settings.json"
    ]).get()
    #expect(options.calibrate == true)
    #expect(options.configOutURL?.path == "/tmp/mactouch-settings.json")
}

@Test func calibrateDefaultsConfigOutToHomeConfig() throws {
    let options = try MacTouchProbeOptions.parse(arguments: ["--calibrate"]).get()
    #expect(options.calibrate == true)
    #expect(options.configOutURL == MacTouchSettings.defaultConfigURL)
}

@Test func parsesConfigForGestures() throws {
    let options = try MacTouchProbeOptions.parse(arguments: [
        "--gestures", "--config", "/tmp/in.json"
    ]).get()
    #expect(options.recognizeGestures == true)
    #expect(options.configURL?.path == "/tmp/in.json")
}
```

Move existing flag parsing logic from `MacTouchProbe.main` into `MacTouchProbeOptions.parse`, preserving current defaults (`duration` 8, `grouping` 0.40, etc.).

- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement parser + refactor `MacTouchProbe` to call it**
- [ ] **Step 4: Run `swift test --filter MacTouchProbeOptionsTests` — PASS; smoke `swift run MacTouchProbe --help`**
- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
Extract MacTouchProbeOptions parsing for calibrate and config flags.

Keeps CLI flag handling testable inside MacTouchCore.
EOF
)"
```

---

### Task 6: Live `--calibrate` wizard + `--config` load path

**Files:**
- Modify: `Sources/MacTouchProbe/MacTouchProbe.swift`
- Modify: `Sources/MacTouchProbe` pipeline init to accept optional `MacTouchSettings` / tap+gesture configs

**Interfaces:**
- Consumes: `CalibrationService`, `MacTouchSettings`, `MacTouchProbeOptions`
- Behavior:
  - If `options.calibrate`: open sensor → `CalibrationService` → print progress when stage/prompt changes → on `.done` call `finish()`, print settings, `save(to: configOutURL)`, exit 0
  - Incomplete / analyzer error → exit 7
  - Save/load I/O error → exit 8
  - If `options.configURL` set for detect/gestures: `load`, apply to detector/gesture configs (override CLI grouping flags when config present — **config wins**; document in README)
  - Mutual exclusion: `--calibrate` cannot combine with `--replay` / `--record` (exit 64)

- [ ] **Step 1: Implement wizard loop (no separate unit test; manual verification)**

Sketch:

```swift
private static func runCalibrate(configOut: URL) {
    let service = SensorService()
    // availability / open same as runLive
    let calibration = CalibrationService()
    var lastPrompt = ""
    // on sample:
    let progress = calibration.ingest(sample)
    if progress.prompt != lastPrompt {
        fputs(progress.prompt + "\n", stderr)
        lastPrompt = progress.prompt
    }
    if progress.stage == .done {
        // stop run loop
    }
    // after stream ends or done:
    do {
        let settings = try calibration.finish()
        print("Recommended settings:")
        print("  minAbsoluteThresholdG=\(settings.minAbsoluteThresholdG)")
        print("  groupingWindow=\(settings.groupingWindow)")
        print("  gestureCooldown=\(settings.gestureCooldown)")
        print("Suggested: swift run MacTouchProbe --gestures --config \(configOut.path)")
        try settings.save(to: configOut)
        fputs("Wrote \(configOut.path)\n", stderr)
        exit(0)
    } catch is CalibrationAnalyzerError {
        exit(7)
    } catch {
        exit(8)
    }
}
```

Use a long max duration (e.g. 120 s) or stop early when stage == `.done`. Prefer stopping early.

Update `SamplePipeline` (or calibrate-specific path) so `--config` applies settings when constructing `TapDetector` / `GestureRecognizer`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success

- [ ] **Step 3: Manual live verification** (on Apple Silicon MacBook)

```bash
swift run MacTouchProbe --calibrate --config-out /tmp/mactouch-settings.json
# Follow prompts: idle, 5 singles, 5 doubles
swift run MacTouchProbe --gestures --config /tmp/mactouch-settings.json --duration 15 --every 100
```

Expected: JSON written; gestures use ~0.27 s grouping for ~0.15 s doubles.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
Wire live --calibrate wizard and --config loading into MacTouchProbe.

Persist recommended settings to JSON and apply them for detect/gestures.
EOF
)"
```

---

### Task 7: Docs — README + handover

**Files:**
- Modify: `README.md`
- Modify: `handover.md`

- [ ] **Step 1: Update README** — add Phase 6 section: `--calibrate`, `--config`, `--config-out`, exit codes 7/8, timing note for ~0.15 s doubles
- [ ] **Step 2: Update handover** — mark Phase 6 done; next = Phase 7 SwiftUI; note settings path
- [ ] **Step 3: Run full test suite**

Run: `swift test`
Expected: all PASS

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
Document Phase 6 calibration CLI and mark handover status.

Point next work at Phase 7 menu-bar UI using MacTouchSettings.
EOF
)"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| `MacTouchSettings` Codable + apply + JSON | Task 1 |
| Analyzer formulas / clamps | Task 2 |
| Stages idle → singles → doubles | Task 3 |
| Sensitive collection detector + façade | Task 4 |
| `--calibrate` / `--config` / `--config-out` | Tasks 5–6 |
| Exit codes 7 / 8 | Task 6 |
| Default `~/.config/MacTouch/settings.json` | Tasks 1, 5 |
| Unit tests (no HID) | Tasks 1–5 |
| README / handover | Task 7 |
| No replay calibrate / no UserDefaults / no SwiftUI | Honored (out of scope) |

**Placeholder scan:** none intentionally left as TBD.

**Type consistency:** `CalibrationStats` → `CalibrationAnalyzer.recommend` → `MacTouchSettings`; session `makeStats()` → same; service `finish()` → same. Gesture field name is `cooldown` on config, `gestureCooldown` on settings (mapped in `apply`).

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-16-calibration.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with executing-plans checkpoints  

Which approach?

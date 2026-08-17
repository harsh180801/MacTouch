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
        try Data(#"{ "version": 99, "minAbsoluteThresholdG": 0.02, "groupingWindow": 0.4, "gestureCooldown": 0.2, "calibratedAt": "2020-01-01T00:00:00Z" }"#.utf8)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MacTouchSettingsError.unsupportedVersion(99)) {
            _ = try MacTouchSettings.load(from: url)
        }
    }

    @Test func loadRejectsInvalidTunedValues() throws {
        let cases: [(name: String, json: String, expected: MacTouchSettingsError)] = [
            (
                "threshold",
                #"{ "version": 1, "minAbsoluteThresholdG": -5, "groupingWindow": 0.4, "gestureCooldown": 0.2, "calibratedAt": "2020-01-01T00:00:00Z" }"#,
                .invalidValue(field: "minAbsoluteThresholdG", value: -5, reason: "must be finite and greater than 0")
            ),
            (
                "grouping",
                #"{ "version": 1, "minAbsoluteThresholdG": 0.02, "groupingWindow": 999, "gestureCooldown": 0.2, "calibratedAt": "2020-01-01T00:00:00Z" }"#,
                .invalidValue(field: "groupingWindow", value: 999, reason: "must be 5.0 seconds or less")
            ),
            (
                "cooldown",
                #"{ "version": 1, "minAbsoluteThresholdG": 0.02, "groupingWindow": 0.4, "gestureCooldown": 0, "calibratedAt": "2020-01-01T00:00:00Z" }"#,
                .invalidValue(field: "gestureCooldown", value: 0, reason: "must be finite and greater than 0")
            )
        ]

        for testCase in cases {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mactouch-invalid-\(testCase.name)-\(UUID().uuidString).json")
            try Data(testCase.json.utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(throws: testCase.expected) {
                _ = try MacTouchSettings.load(from: url)
            }
        }
    }

    @Test func settingsErrorLocalizedDescriptionContainsUsefulText() {
        let version = MacTouchSettingsError.unsupportedVersion(99).localizedDescription
        let invalid = MacTouchSettingsError.invalidValue(
            field: "groupingWindow",
            value: -1,
            reason: "must be finite and greater than 0"
        ).localizedDescription
        let io = MacTouchSettingsError.ioFailed("permission denied").localizedDescription

        #expect(version.contains("unsupported settings version 99"))
        #expect(invalid.contains("groupingWindow"))
        #expect(invalid.contains("must be finite and greater than 0"))
        #expect(io.contains("permission denied"))
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

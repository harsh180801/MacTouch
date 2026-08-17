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

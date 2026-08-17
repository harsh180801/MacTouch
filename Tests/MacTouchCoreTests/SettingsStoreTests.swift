import Foundation
import Testing
@testable import MacTouchCore

struct SettingsStoreTests {
    @Test func loadOrDefaultFallsBackWhenMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-missing-\(UUID().uuidString).json")
        let store = SettingsStore(url: url)
        let settings = store.loadOrDefault()
        #expect(settings.minAbsoluteThresholdG > 0)
        #expect(settings.groupingWindow > 0)
    }

    @Test func roundTripSaveLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(url: url)
        let original = MacTouchSettings(
            minAbsoluteThresholdG: 0.028,
            groupingWindow: 0.29,
            gestureCooldown: 0.17,
            calibratedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(original)
        let loaded = try store.load()
        #expect(loaded.minAbsoluteThresholdG == 0.028)
        #expect(loaded.groupingWindow == 0.29)
        #expect(loaded.gestureCooldown == 0.17)
    }
}

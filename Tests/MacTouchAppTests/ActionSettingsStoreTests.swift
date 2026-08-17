import Foundation
import Testing
@testable import MacTouchApp

struct ActionSettingsStoreTests {
    @Test func roundTripSaveLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-actions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActionSettingsStore(url: url)
        let settings = ActionSettings(
            enabled: true,
            singleShortcutName: "  Single Action  ",
            doubleShortcutName: "Double Action",
            tripleShortcutName: nil,
            cooldownSeconds: 1.8
        )

        try store.save(settings)
        let loaded = try store.load()
        #expect(loaded.enabled)
        #expect(loaded.singleShortcutName == "Single Action")
        #expect(loaded.doubleShortcutName == "Double Action")
        #expect(loaded.tripleShortcutName == nil)
        #expect(loaded.cooldownSeconds == 1.8)
    }

    @Test func rejectsInvalidCooldown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-actions-invalid-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let bad = """
        {
          "enabled" : true,
          "singleShortcutName" : "A",
          "doubleShortcutName" : null,
          "tripleShortcutName" : null,
          "cooldownSeconds" : 0
        }
        """
        try Data(bad.utf8).write(to: url)
        let store = ActionSettingsStore(url: url)
        #expect(throws: ActionSettingsError.self) {
            _ = try store.load()
        }
    }
}

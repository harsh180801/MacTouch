import Foundation
import MacTouchCore

struct ActionSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var singleShortcutName: String?
    var doubleShortcutName: String?
    var tripleShortcutName: String?
    var cooldownSeconds: Double

    init(
        enabled: Bool = false,
        singleShortcutName: String? = nil,
        doubleShortcutName: String? = nil,
        tripleShortcutName: String? = nil,
        cooldownSeconds: Double = 1.2
    ) {
        self.enabled = enabled
        self.singleShortcutName = ActionSettings.normalizedName(singleShortcutName)
        self.doubleShortcutName = ActionSettings.normalizedName(doubleShortcutName)
        self.tripleShortcutName = ActionSettings.normalizedName(tripleShortcutName)
        self.cooldownSeconds = cooldownSeconds
    }

    mutating func normalize() {
        singleShortcutName = ActionSettings.normalizedName(singleShortcutName)
        doubleShortcutName = ActionSettings.normalizedName(doubleShortcutName)
        tripleShortcutName = ActionSettings.normalizedName(tripleShortcutName)
    }

    func shortcutName(for kind: TapGestureKind) -> String? {
        switch kind {
        case .single: singleShortcutName
        case .double: doubleShortcutName
        case .triple: tripleShortcutName
        }
    }

    static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ActionSettingsError: Error, LocalizedError {
    case decodeFailed
    case encodeFailed
    case ioFailed(String)
    case invalidCooldown(Double)

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "failed to decode action settings JSON"
        case .encodeFailed:
            return "failed to encode action settings JSON"
        case .ioFailed(let reason):
            return "action settings I/O failed: \(reason)"
        case .invalidCooldown(let value):
            return "invalid action cooldown \(value); must be finite and > 0"
        }
    }
}

struct ActionSettingsStore: Sendable {
    var url: URL

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("MacTouch")
            .appendingPathComponent("actions.json")
    }

    func loadOrDefault() -> ActionSettings {
        do {
            return try load()
        } catch {
            return ActionSettings()
        }
    }

    func load() throws -> ActionSettings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ActionSettingsError.ioFailed(error.localizedDescription)
        }

        let settings: ActionSettings
        do {
            settings = try JSONDecoder().decode(ActionSettings.self, from: data)
        } catch {
            throw ActionSettingsError.decodeFailed
        }

        try validate(settings)
        var normalized = settings
        normalized.normalize()
        return normalized
    }

    func save(_ settings: ActionSettings) throws {
        try validate(settings)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ActionSettingsError.ioFailed(error.localizedDescription)
        }

        var normalized = settings
        normalized.normalize()

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(normalized)
        } catch {
            throw ActionSettingsError.encodeFailed
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ActionSettingsError.ioFailed(error.localizedDescription)
        }
    }

    private func validate(_ settings: ActionSettings) throws {
        guard settings.cooldownSeconds.isFinite, settings.cooldownSeconds > 0 else {
            throw ActionSettingsError.invalidCooldown(settings.cooldownSeconds)
        }
    }
}

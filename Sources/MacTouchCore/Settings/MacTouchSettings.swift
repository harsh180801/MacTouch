import Foundation

public enum MacTouchSettingsError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int)
    case encodeFailed
    case decodeFailed
    case ioFailed(String)
    case invalidValue(field: String, value: Double, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "unsupported settings version \(version); expected \(MacTouchSettings.currentVersion)"
        case .encodeFailed:
            return "failed to encode settings JSON"
        case .decodeFailed:
            return "failed to decode settings JSON"
        case .ioFailed(let reason):
            return "settings I/O failed: \(reason)"
        case .invalidValue(let field, let value, let reason):
            return "invalid settings value \(field)=\(value): \(reason)"
        }
    }
}

public struct MacTouchSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    private static let maximumLoadedThresholdG = 1.0
    private static let maximumLoadedDurationSeconds = 5.0

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
        try settings.validateLoadedValues()
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

    private func validateLoadedValues() throws {
        try validatePositiveFinite(
            minAbsoluteThresholdG,
            field: "minAbsoluteThresholdG",
            maximum: Self.maximumLoadedThresholdG,
            maximumDescription: "must be \(Self.maximumLoadedThresholdG) g or less"
        )
        try validatePositiveFinite(
            groupingWindow,
            field: "groupingWindow",
            maximum: Self.maximumLoadedDurationSeconds,
            maximumDescription: "must be \(Self.maximumLoadedDurationSeconds) seconds or less"
        )
        try validatePositiveFinite(
            gestureCooldown,
            field: "gestureCooldown",
            maximum: Self.maximumLoadedDurationSeconds,
            maximumDescription: "must be \(Self.maximumLoadedDurationSeconds) seconds or less"
        )
    }

    private func validatePositiveFinite(
        _ value: Double,
        field: String,
        maximum: Double,
        maximumDescription: String
    ) throws {
        guard value.isFinite, value > 0 else {
            throw MacTouchSettingsError.invalidValue(
                field: field,
                value: value,
                reason: "must be finite and greater than 0"
            )
        }
        guard value <= maximum else {
            throw MacTouchSettingsError.invalidValue(field: field, value: value, reason: maximumDescription)
        }
    }
}

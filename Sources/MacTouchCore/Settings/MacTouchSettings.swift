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

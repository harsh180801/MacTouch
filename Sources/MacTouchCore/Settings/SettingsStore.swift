import Foundation

/// Loads and saves `MacTouchSettings` JSON (shared with CLI `--config` / `--calibrate`).
public struct SettingsStore: Sendable {
    public var url: URL

    public init(url: URL = MacTouchSettings.defaultConfigURL) {
        self.url = url
    }

    public func load() throws -> MacTouchSettings {
        try MacTouchSettings.load(from: url)
    }

    /// Returns on-disk settings when present and valid; otherwise built-in defaults.
    public func loadOrDefault() -> MacTouchSettings {
        do {
            return try load()
        } catch {
            return MacTouchSettings(
                minAbsoluteThresholdG: TapDetectorConfig().minAbsoluteThresholdG,
                groupingWindow: GestureRecognizerConfig().groupingWindow,
                gestureCooldown: GestureRecognizerConfig().cooldown
            )
        }
    }

    public func save(_ settings: MacTouchSettings) throws {
        try settings.save(to: url)
    }
}

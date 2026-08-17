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

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

import Foundation
import Testing
@testable import MacTouchCore

struct CalibrationServiceTests {
    @Test func collectionTapConfigIsMoreSensitiveThanDefaults() {
        let collection = CalibrationService.collectionTapConfig()
        let defaults = TapDetectorConfig()
        #expect(collection.minAbsoluteThresholdG < defaults.minAbsoluteThresholdG)
        #expect(collection.minConfidence <= defaults.minConfidence)
    }

    @Test func finishThrowsIfNotDone() {
        let service = CalibrationService(
            sessionConfig: CalibrationSessionConfig(idleDurationSeconds: 10, idleWarmupSeconds: 0)
        )
        service.start(at: 0)
        #expect(throws: CalibrationAnalyzerError.self) {
            _ = try service.finish()
        }
    }

    @Test func ingestAdvancesIdleWithoutTaps() {
        let service = CalibrationService(
            sessionConfig: CalibrationSessionConfig(idleDurationSeconds: 0.1, idleWarmupSeconds: 0)
        )
        service.start(at: 0)

        let progress = service.ingest(SensorSample(timestamp: 0.11, x: 0, y: 0, z: -1))

        #expect(progress.stage == .singles)
    }
}

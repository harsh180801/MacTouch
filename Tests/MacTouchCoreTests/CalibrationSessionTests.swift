import Foundation
import Testing
@testable import MacTouchCore

struct CalibrationSessionTests {
    private func tap(at t: TimeInterval, peak: Double = 0.06) -> TapEvent {
        TapEvent(
            timestamp: t,
            peakStrength: peak,
            peakLinearMagnitude: peak,
            peakJerk: 20,
            duration: 0.02,
            confidence: 0.5,
            reasons: ["test"]
        )
    }

    @Test func idleAdvancesAfterDuration() {
        let session = CalibrationSession(
            config: CalibrationSessionConfig(idleDurationSeconds: 1.0, idleWarmupSeconds: 0.2)
        )
        session.start(at: 0)
        // During warmup — magnitudes ignored for stats
        session.ingest(filteredMagnitude: 0.05, timestamp: 0.1)
        // After warmup — collect quiet samples
        for i in 0..<50 {
            session.ingest(filteredMagnitude: 0.008, timestamp: 0.3 + Double(i) * 0.01)
        }
        let mid = session.poll(now: 0.5)
        #expect(mid.stage == .idle)
        let after = session.poll(now: 1.05)
        #expect(after.stage == .singles)
    }

    @Test func singlesRequireIsolatedTaps() {
        let session = CalibrationSession(
            config: CalibrationSessionConfig(idleDurationSeconds: 0.1, idleWarmupSeconds: 0)
        )
        session.start(at: 0)
        _ = session.poll(now: 0.15) // → singles
        // Two taps 0.15s apart — second should NOT count as a new single
        session.ingest(tap: tap(at: 1.0, peak: 0.05))
        session.ingest(tap: tap(at: 1.15, peak: 0.05))
        #expect(session.poll(now: 1.2).singleCount == 1)
        session.ingest(tap: tap(at: 2.0, peak: 0.06))
        #expect(session.poll(now: 2.1).singleCount == 2)
    }

    @Test func doublesPairCloseGapsAndFinish() {
        var config = CalibrationSessionConfig(idleDurationSeconds: 0.05, idleWarmupSeconds: 0)
        config.requiredSingles = 2
        config.requiredDoubles = 2
        let session = CalibrationSession(config: config)
        session.start(at: 0)
        _ = session.poll(now: 0.1)
        // Complete singles quickly
        session.ingest(tap: tap(at: 1.0))
        session.ingest(tap: tap(at: 2.0))
        #expect(session.poll(now: 2.1).stage == .doubles)
        // Pair 1
        session.ingest(tap: tap(at: 3.0))
        session.ingest(tap: tap(at: 3.15))
        // Pair 2
        session.ingest(tap: tap(at: 4.5))
        session.ingest(tap: tap(at: 4.65))
        let done = session.poll(now: 4.7)
        #expect(done.stage == .done)
        #expect(done.doublePairCount == 2)
        let stats = try! session.makeStats()
        #expect(stats.doubleGaps.count == 2)
        #expect(abs(stats.doubleGaps[0] - 0.15) < 0.001)
    }
}

import Foundation
import Testing
@testable import MacTouchCore

struct SignalProcessorTests {
    @Test func magnitudeMatchesHypotenuse() {
        #expect(abs(SignalMath.magnitude(3, 4, 0) - 5) < 1e-12)
        #expect(abs(SensorSample(timestamp: 0, x: 0, y: 0, z: 1).magnitude - 1) < 1e-12)
    }

    @Test func emaAlphaIsBetweenZeroAndOne() {
        let alpha = SignalMath.emaAlpha(timeConstantSeconds: 0.5, sampleRateHz: 800)
        #expect(alpha > 0.9)
        #expect(alpha < 1.0)
    }

    @Test func lowPassSmoothsStepAfterTransient() {
        var filter = FirstOrderLowPass(cutoffHz: 5, sampleRateHz: 100)
        var last = 0.0
        for i in 0..<200 {
            last = filter.process(i == 0 ? 0 : 1)
        }
        #expect(last > 0.9)
        #expect(last <= 1.0)
    }

    @Test func highPassRejectsConstantGravityLikeBias() {
        var hp = FirstOrderHighPass3(cutoffHz: 10, sampleRateHz: 200)
        var lastMag = 0.0
        for _ in 0..<400 {
            let out = hp.process(x: 0, y: 0, z: 1) // constant "1g"
            lastMag = SignalMath.magnitude(out.x, out.y, out.z)
        }
        #expect(lastMag < 0.05)
    }

    @Test func highPassPassesImpulse() {
        var hp = FirstOrderHighPass3(cutoffHz: 10, sampleRateHz: 200)
        // Settle on baseline.
        for _ in 0..<100 {
            _ = hp.process(x: 0, y: 0, z: 0)
        }
        let impulse = hp.process(x: 0, y: 0, z: 1)
        let impulseMag = SignalMath.magnitude(impulse.x, impulse.y, impulse.z)
        #expect(impulseMag > 0.5)
    }

    @Test func gravityRemovalLeavesNearZeroAtRest() {
        let processor = SignalProcessor(
            config: SignalProcessorConfig(
                sampleRateHz: 200,
                gravityTimeConstantSeconds: 0.2,
                impactHighPassCutoffHz: 10,
                impactLowPassCutoffHz: nil,
                noiseFloorTimeConstantSeconds: 0.5
            )
        )
        var last: ProcessedSample?
        for i in 0..<400 {
            let t = Double(i) / 200
            // Steady tilt: gravity only.
            last = processor.process(SensorSample(timestamp: t, x: 0.1, y: -0.2, z: -0.97))
        }
        #expect(last != nil)
        #expect(last!.linearMagnitude < 0.05)
        #expect(last!.filteredMagnitude < 0.05)
        #expect(abs(last!.rawMagnitude - 1.0) < 0.05)
    }

    @Test func impulseRaisesFilteredMagnitudeAboveNoiseFloor() {
        let processor = SignalProcessor(
            config: SignalProcessorConfig(
                sampleRateHz: 200,
                gravityTimeConstantSeconds: 0.25,
                impactHighPassCutoffHz: 10,
                impactLowPassCutoffHz: 80,
                noiseFloorTimeConstantSeconds: 0.5
            )
        )

        // Quiet baseline.
        for i in 0..<300 {
            let t = Double(i) / 200
            _ = processor.process(SensorSample(timestamp: t, x: 0, y: 0, z: -1))
        }

        // Sharp tap-like spike on Z.
        let spike = processor.process(SensorSample(timestamp: 1.5, x: 0, y: 0, z: -1 + 0.8))
        #expect(spike.filteredMagnitude > spike.noiseFloor + 0.05)
        #expect(spike.normalizedExcess > 1)
        #expect(spike.linearMagnitude > 0.3)
    }

    @Test func noiseFloorDoesNotJumpOnSingleSpike() {
        let processor = SignalProcessor(
            config: SignalProcessorConfig(
                sampleRateHz: 200,
                gravityTimeConstantSeconds: 0.25,
                impactHighPassCutoffHz: 10,
                impactLowPassCutoffHz: nil,
                noiseFloorTimeConstantSeconds: 1.0,
                elevatedSigma: 4,
                elevatedMarginG: 0.02
            )
        )

        for i in 0..<400 {
            _ = processor.process(SensorSample(timestamp: Double(i) / 200, x: 0, y: 0, z: -1))
        }
        let before = processor.process(SensorSample(timestamp: 2.0, x: 0, y: 0, z: -1))
        let floorBefore = before.noiseFloor

        _ = processor.process(SensorSample(timestamp: 2.005, x: 0, y: 0, z: -1 + 1.0))
        let after = processor.process(SensorSample(timestamp: 2.01, x: 0, y: 0, z: -1))

        // Floor should stay close; spike must not instantly become the new baseline.
        #expect(abs(after.noiseFloor - floorBefore) < 0.05)
    }

    @Test func resetClearsState() {
        let processor = SignalProcessor()
        _ = processor.process(SensorSample(timestamp: 0, x: 0, y: 0, z: -1))
        processor.reset()
        let first = processor.process(SensorSample(timestamp: 0, x: 0, y: 0, z: -1))
        // After reset, gravity initializes to the first sample → linear ≈ 0.
        #expect(first.linearMagnitude < 1e-9)
    }
}

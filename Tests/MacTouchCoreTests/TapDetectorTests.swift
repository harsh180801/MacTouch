import Foundation
import Testing
@testable import MacTouchCore

struct TapDetectorTests {
    private func makeProcessor() -> SignalProcessor {
        SignalProcessor(
            config: SignalProcessorConfig(
                sampleRateHz: 200,
                gravityTimeConstantSeconds: 0.2,
                impactHighPassCutoffHz: 10,
                impactLowPassCutoffHz: nil,
                noiseFloorTimeConstantSeconds: 0.4
            )
        )
    }

    private func makeDetector() -> TapDetector {
        TapDetector(
            config: TapDetectorConfig(
                sampleRateHz: 200,
                thresholdSigma: 5,
                minAbsoluteThresholdG: 0.025,
                decayFraction: 0.45,
                maxImpactDurationSeconds: 0.10,
                debounceSeconds: 0.12,
                warmupSeconds: 0.25,
                minJerkGPerSecond: 6,
                hardLinearAmplitudeG: 0.30,
                sustainedMotionLimitG: 0.08,
                sustainedMotionWindowSeconds: 0.30,
                preImpactQuietSeconds: 0.10,
                minConfidence: 0.30
            )
        )
    }

    private func sample(t: TimeInterval, spikeZ: Double = 0) -> SensorSample {
        SensorSample(timestamp: t, x: 0, y: 0, z: -1 + spikeZ)
    }

    /// Build a processed frame without running the streaming filters (deterministic unit tests).
    private func processed(
        t: TimeInterval,
        filtered: Double,
        linear: Double,
        noiseFloor: Double = 0.005,
        noiseDeviation: Double = 0.002
    ) -> ProcessedSample {
        ProcessedSample(
            timestamp: t,
            x: 0,
            y: 0,
            z: -1,
            rawMagnitude: 1,
            linearX: 0,
            linearY: 0,
            linearZ: linear,
            linearMagnitude: abs(linear),
            filteredMagnitude: filtered,
            noiseFloor: noiseFloor,
            noiseDeviation: noiseDeviation,
            normalizedExcess: max(0, (filtered - noiseFloor) / max(noiseDeviation, 1e-6))
        )
    }

    @Test func detectsSharpImpulseAfterWarmup() {
        let processor = makeProcessor()
        let detector = makeDetector()
        var events: [TapEvent] = []

        for i in 0..<80 {
            let t = Double(i) / 200
            if let event = detector.process(processor.process(sample(t: t))) {
                events.append(event)
            }
        }

        let spikeT = 80.0 / 200
        if let event = detector.process(processor.process(sample(t: spikeT, spikeZ: 0.9))) {
            events.append(event)
        }
        for i in 81..<140 {
            let t = Double(i) / 200
            if let event = detector.process(processor.process(sample(t: t))) {
                events.append(event)
            }
        }

        #expect(events.count == 1)
        #expect(events[0].peakStrength > 0.05)
        #expect(events[0].confidence >= 0.30)
    }

    @Test func debounceSuppressesImmediateSecondPeak() {
        let processor = makeProcessor()
        let detector = makeDetector()
        var events: [TapEvent] = []

        func feed(_ t: TimeInterval, spike: Double = 0) {
            if let event = detector.process(processor.process(sample(t: t, spikeZ: spike))) {
                events.append(event)
            }
        }

        for i in 0..<70 { feed(Double(i) / 200) }
        feed(0.35, spike: 0.85)
        for i in 71..<76 { feed(Double(i) / 200) }
        feed(0.40, spike: 0.85)
        for i in 81..<140 { feed(Double(i) / 200) }

        #expect(events.count == 1)
    }

    @Test func rejectsSustainedHighLinearMotion() {
        let detector = TapDetector(
            config: TapDetectorConfig(
                sampleRateHz: 200,
                minAbsoluteThresholdG: 0.03,
                maxImpactDurationSeconds: 0.08,
                debounceSeconds: 0.05,
                warmupSeconds: 0.2,
                minJerkGPerSecond: 5,
                hardLinearAmplitudeG: 0.5,
                sustainedMotionLimitG: 0.12,
                sustainedMotionWindowSeconds: 0.25,
                preImpactQuietSeconds: 0.1,
                minConfidence: 0.2
            )
        )

        var events: [TapEvent] = []
        for i in 0..<50 {
            let t = Double(i) / 200
            if let event = detector.process(processed(t: t, filtered: 0.004, linear: 0.01)) {
                events.append(event)
            }
        }
        // Sustained elevated linear motion (above light-tap peaks).
        for i in 50..<120 {
            let t = Double(i) / 200
            if let event = detector.process(processed(t: t, filtered: 0.05, linear: 0.18)) {
                events.append(event)
            }
        }

        #expect(events.isEmpty)
    }

    @Test func rejectsLowAmplitudeTypingLikeFrames() {
        let detector = TapDetector(
            config: TapDetectorConfig(
                sampleRateHz: 200,
                minAbsoluteThresholdG: 0.03,
                warmupSeconds: 0.2,
                minJerkGPerSecond: 12,
                hardLinearAmplitudeG: 0.4,
                preImpactQuietSeconds: 0.08,
                minConfidence: 0.35
            )
        )

        var events: [TapEvent] = []
        for i in 0..<50 {
            _ = detector.process(processed(t: Double(i) / 200, filtered: 0.004, linear: 0.01))
        }
        // Soft rocks: enough to cross a low threshold visually, but weak jerk / amp.
        for i in 50..<150 {
            let t = Double(i) / 200
            let pulse = (i % 8 == 0)
            let filtered = pulse ? 0.035 : 0.004
            let linear = pulse ? 0.04 : 0.01
            if let event = detector.process(processed(t: t, filtered: filtered, linear: linear)) {
                events.append(event)
            }
        }

        #expect(events.isEmpty)
    }

    @Test func rejectsImpactThatTimesOutWithoutDecay() {
        let detector = TapDetector(
            config: TapDetectorConfig(
                sampleRateHz: 200,
                minAbsoluteThresholdG: 0.02,
                maxImpactDurationSeconds: 0.05,
                debounceSeconds: 0.05,
                warmupSeconds: 0.15,
                minJerkGPerSecond: 1,
                hardLinearAmplitudeG: 0.1,
                sustainedMotionLimitG: 1.0,
                preImpactQuietSeconds: 0.05,
                minConfidence: 0.1
            )
        )

        var events: [TapEvent] = []
        for i in 0..<40 {
            _ = detector.process(processed(t: Double(i) / 200, filtered: 0.003, linear: 0.01))
        }
        // Hold filtered magnitude high until timeout (no decay).
        for i in 40..<60 {
            let t = Double(i) / 200
            if let event = detector.process(processed(t: t, filtered: 0.2, linear: 0.25)) {
                events.append(event)
            }
        }

        #expect(events.isEmpty)
    }

    @Test func acceptsSyntheticImpulseWithDecay() {
        let detector = TapDetector(
            config: TapDetectorConfig(
                sampleRateHz: 200,
                minAbsoluteThresholdG: 0.03,
                maxImpactDurationSeconds: 0.1,
                debounceSeconds: 0.1,
                warmupSeconds: 0.15,
                minJerkGPerSecond: 5,
                hardLinearAmplitudeG: 0.5,
                sustainedMotionLimitG: 0.2,
                preImpactQuietSeconds: 0.08,
                minConfidence: 0.25
            )
        )

        var events: [TapEvent] = []
        for i in 0..<40 {
            _ = detector.process(processed(t: Double(i) / 200, filtered: 0.004, linear: 0.01))
        }
        // Rise
        _ = detector.process(processed(t: 0.20, filtered: 0.12, linear: 0.20))
        // Peak
        _ = detector.process(processed(t: 0.205, filtered: 0.18, linear: 0.28))
        // Decay
        if let event = detector.process(processed(t: 0.22, filtered: 0.02, linear: 0.03)) {
            events.append(event)
        }

        #expect(events.count == 1)
        #expect(events[0].peakStrength >= 0.18)
        #expect(events[0].duration < 0.05)
    }

    @Test func detectsRealLightTapRecordingIfPresent() throws {
        let url = URL(fileURLWithPath: "Recordings/taps.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Local capture only; skip when absent in CI.
            return
        }

        let recording = try SensorRecordingIO.read(from: url)
        let processor = SignalProcessor()
        let detector = TapDetector()
        var events: [TapEvent] = []
        for sample in recording.samples {
            let processed = processor.process(sample)
            if let event = detector.process(processed) {
                events.append(event)
            }
        }

        #expect(events.count >= 1)
        #expect(events.allSatisfy { $0.peakStrength >= 0.02 })
    }

    @Test func resetAllowsDetectionAgain() {
        let processor = makeProcessor()
        let detector = makeDetector()

        for i in 0..<80 {
            _ = detector.process(processor.process(sample(t: Double(i) / 200)))
        }
        _ = detector.process(processor.process(sample(t: 0.4, spikeZ: 0.9)))
        for i in 81..<100 {
            _ = detector.process(processor.process(sample(t: Double(i) / 200)))
        }

        detector.reset()
        processor.reset()

        var events: [TapEvent] = []
        for i in 0..<80 {
            _ = detector.process(processor.process(sample(t: Double(i) / 200)))
        }
        if let event = detector.process(processor.process(sample(t: 0.4, spikeZ: 0.9))) {
            events.append(event)
        }
        for i in 81..<140 {
            if let event = detector.process(processor.process(sample(t: Double(i) / 200))) {
                events.append(event)
            }
        }

        #expect(events.count >= 1)
    }
}

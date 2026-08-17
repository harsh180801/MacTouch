import Foundation

public final class CalibrationService {
    private let processor: SignalProcessor
    private let detector: TapDetector
    private let session: CalibrationSession
    private var hasStarted = false

    public static func collectionTapConfig() -> TapDetectorConfig {
        var config = TapDetectorConfig()
        config.minAbsoluteThresholdG = 0.012
        config.minConfidence = 0.15
        return config
    }

    public init(sessionConfig: CalibrationSessionConfig = CalibrationSessionConfig()) {
        self.processor = SignalProcessor()
        self.detector = TapDetector(config: Self.collectionTapConfig())
        self.session = CalibrationSession(config: sessionConfig)
    }

    public func start(at timestamp: TimeInterval) {
        processor.reset()
        detector.reset()
        session.start(at: timestamp)
        hasStarted = true
    }

    public func ingest(_ sample: SensorSample) -> CalibrationProgress {
        precondition(hasStarted, "CalibrationService.start(at:) must be called before ingest(_:).")

        let processed = processor.process(sample)
        session.ingest(filteredMagnitude: processed.filteredMagnitude, timestamp: processed.timestamp)
        if let tap = detector.process(processed) {
            session.ingest(tap: tap)
        }
        return session.poll(now: processed.timestamp)
    }

    public func finish() throws -> MacTouchSettings {
        let stats = try session.makeStats()
        return try CalibrationAnalyzer.recommend(from: stats)
    }
}

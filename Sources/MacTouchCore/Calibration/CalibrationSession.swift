import Foundation

public enum CalibrationSessionError: Error, Equatable, Sendable {
    case incomplete
}

public final class CalibrationSession {
    public private(set) var config: CalibrationSessionConfig

    private var stage: CalibrationStage = .idle
    private var stageStartedAt: TimeInterval?
    private var idleMagnitudes: [Double] = []
    private var idleP95 = 0.0
    private var singlePeaks: [Double] = []
    private var lastAcceptedSingle: TimeInterval?
    private var doubleGaps: [TimeInterval] = []
    private var pendingDoubleTap: TapEvent?

    public init(config: CalibrationSessionConfig = CalibrationSessionConfig()) {
        self.config = config
    }

    public func start(at timestamp: TimeInterval) {
        stage = .idle
        stageStartedAt = timestamp
        idleMagnitudes.removeAll()
        idleP95 = 0
        singlePeaks.removeAll()
        lastAcceptedSingle = nil
        doubleGaps.removeAll()
        pendingDoubleTap = nil
    }

    public func ingest(filteredMagnitude: Double, timestamp: TimeInterval) {
        guard stage == .idle, let stageStartedAt else { return }
        guard timestamp - stageStartedAt >= config.idleWarmupSeconds else { return }
        idleMagnitudes.append(filteredMagnitude)
    }

    public func ingest(tap: TapEvent) {
        switch stage {
        case .idle, .done:
            return
        case .singles:
            ingestSingle(tap)
        case .doubles:
            ingestDouble(tap)
        }
    }

    public func poll(now: TimeInterval) -> CalibrationProgress {
        advanceIdleIfNeeded(now: now)
        return makeProgress()
    }

    public func makeStats() throws -> CalibrationStats {
        guard stage == .done else {
            throw CalibrationSessionError.incomplete
        }
        return CalibrationStats(
            idleP95: idleP95,
            singlePeaks: singlePeaks,
            doubleGaps: doubleGaps
        )
    }

    private func advanceIdleIfNeeded(now: TimeInterval) {
        guard stage == .idle, let stageStartedAt else { return }
        guard now - stageStartedAt >= config.idleDurationSeconds else { return }

        idleP95 = percentile95(idleMagnitudes)
        stage = .singles
        self.stageStartedAt = now
    }

    private func ingestSingle(_ tap: TapEvent) {
        if let lastAcceptedSingle, tap.timestamp - lastAcceptedSingle < config.singleMinGapSeconds {
            return
        }

        singlePeaks.append(tap.peakStrength)
        lastAcceptedSingle = tap.timestamp

        if singlePeaks.count >= config.requiredSingles {
            stage = .doubles
            stageStartedAt = tap.timestamp
            pendingDoubleTap = nil
        }
    }

    private func ingestDouble(_ tap: TapEvent) {
        guard let pendingDoubleTap else {
            self.pendingDoubleTap = tap
            return
        }

        let gap = tap.timestamp - pendingDoubleTap.timestamp
        if gap >= config.doubleMinGapSeconds && gap <= config.doubleMaxGapSeconds {
            doubleGaps.append(gap)
            self.pendingDoubleTap = nil
            if doubleGaps.count >= config.requiredDoubles {
                stage = .done
                stageStartedAt = tap.timestamp
            }
            return
        }

        self.pendingDoubleTap = tap
    }

    private func makeProgress() -> CalibrationProgress {
        CalibrationProgress(
            stage: stage,
            prompt: prompt,
            idleSamples: idleMagnitudes.count,
            singleCount: singlePeaks.count,
            doublePairCount: doubleGaps.count,
            requiredSingles: config.requiredSingles,
            requiredDoubles: config.requiredDoubles
        )
    }

    private var prompt: String {
        switch stage {
        case .idle:
            return "Keep still — do not tap."
        case .singles:
            return "Tap once, pause ~1s, repeat (\(singlePeaks.count)/\(config.requiredSingles))."
        case .doubles:
            return "Double-tap (~0.15s apart), then pause (\(doubleGaps.count)/\(config.requiredDoubles))."
        case .done:
            return "Calibration complete."
        }
    }

    private func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(0.95 * Double(sorted.count - 1))
        return sorted[index]
    }
}

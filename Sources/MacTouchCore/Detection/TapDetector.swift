import Foundation

/// A single physical chassis impact (not yet grouped into double/triple gestures).
public struct TapEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: TimeInterval
    /// Peak filtered magnitude during the impact (g).
    public let peakStrength: Double
    /// Peak linear magnitude during the impact (g).
    public let peakLinearMagnitude: Double
    /// Peak jerk estimate during the impact (g/s).
    public let peakJerk: Double
    /// How long the signal stayed above the entry threshold (seconds).
    public let duration: TimeInterval
    /// 0…1 score combining strength, sharpness, and brevity.
    public let confidence: Double
    /// Human-readable reasons that contributed to acceptance.
    public let reasons: [String]

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        peakStrength: Double,
        peakLinearMagnitude: Double,
        peakJerk: Double,
        duration: TimeInterval,
        confidence: Double,
        reasons: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.peakStrength = peakStrength
        self.peakLinearMagnitude = peakLinearMagnitude
        self.peakJerk = peakJerk
        self.duration = duration
        self.confidence = confidence
        self.reasons = reasons
    }
}

/// Tunable tap-detection parameters. Defaults are starting points for light chassis taps.
public struct TapDetectorConfig: Equatable, Sendable {
    /// Assumed sample rate (Hz). Used for jerk and sample-window conversions.
    public var sampleRateHz: Double

    /// Minimum filtered-magnitude rise above the noise floor to start an impact.
    /// Effective threshold = max(minAbsoluteThresholdG, noiseFloor + thresholdSigma * noiseDeviation).
    public var thresholdSigma: Double

    /// Absolute floor (g) so a near-zero noise estimate cannot fire on tiny jitter.
    public var minAbsoluteThresholdG: Double

    /// Require filtered magnitude to fall below `peak * decayFraction` (or absolute
    /// threshold) before emitting — confirms an impulse rather than a plateau.
    public var decayFraction: Double

    /// Maximum time spent above threshold for one physical tap (seconds).
    /// Longer activations are treated as sustained movement / relocation.
    public var maxImpactDurationSeconds: Double

    /// Minimum gap between accepted taps (debounce / refractory).
    public var debounceSeconds: Double

    /// Warm-up period before any detection (lets gravity + noise floor settle).
    public var warmupSeconds: Double

    /// Minimum jerk (g/s) for a soft tap. Typing often has amplitude without co-occurring
    /// high jerk (MacSlapApp empirical observation); require both unless hardAmp fires.
    public var minJerkGPerSecond: Double

    /// Linear magnitude so large we accept even if jerk is modest (hard knock).
    public var hardLinearAmplitudeG: Double

    /// Reject if low-frequency linear magnitude stays high over a short lookback
    /// (lid adjust / picking up the laptop). Compared against mean linear magnitude.
    public var sustainedMotionLimitG: Double

    /// Lookback window for sustained-motion rejection (seconds).
    public var sustainedMotionWindowSeconds: Double

    /// Require the filtered signal to be quiet for this long before an impact may start.
    /// Helps reject the onset of a continuous shove / relocation.
    public var preImpactQuietSeconds: Double

    /// Exclude this many seconds immediately before threshold crossing from the quiet check
    /// so the tap's rising edge does not fail the quiet gate.
    public var preImpactQuietTailExclusionSeconds: Double

    /// Minimum confidence required to publish an event.
    public var minConfidence: Double

    public init(
        sampleRateHz: Double = 800,
        // Tuned from real light-tap capture on MacBook Pro M4 Pro (Recordings/taps.csv):
        // peak filtered ≈ 0.05–0.07 g, peak linear ≈ 0.07–0.09 g.
        thresholdSigma: Double = 5,
        minAbsoluteThresholdG: Double = 0.02,
        decayFraction: Double = 0.50,
        maxImpactDurationSeconds: Double = 0.15,
        debounceSeconds: Double = 0.12,
        warmupSeconds: Double = 0.35,
        minJerkGPerSecond: Double = 4,
        hardLinearAmplitudeG: Double = 0.10,
        // Pre-impact only. Must stay above typical tap linear peaks (~0.09 g) so the
        // tap itself is not mistaken for sustained motion.
        sustainedMotionLimitG: Double = 0.12,
        sustainedMotionWindowSeconds: Double = 0.30,
        // Pre-impact quiet window. Exclude a short tail so the tap's own rising
        // edge is not treated as "not quiet" (measured failure mode on light taps).
        preImpactQuietSeconds: Double = 0.08,
        preImpactQuietTailExclusionSeconds: Double = 0.025,
        minConfidence: Double = 0.22
    ) {
        self.sampleRateHz = sampleRateHz
        self.thresholdSigma = thresholdSigma
        self.minAbsoluteThresholdG = minAbsoluteThresholdG
        self.decayFraction = decayFraction
        self.maxImpactDurationSeconds = maxImpactDurationSeconds
        self.debounceSeconds = debounceSeconds
        self.warmupSeconds = warmupSeconds
        self.minJerkGPerSecond = minJerkGPerSecond
        self.hardLinearAmplitudeG = hardLinearAmplitudeG
        self.sustainedMotionLimitG = sustainedMotionLimitG
        self.sustainedMotionWindowSeconds = sustainedMotionWindowSeconds
        self.preImpactQuietSeconds = preImpactQuietSeconds
        self.preImpactQuietTailExclusionSeconds = preImpactQuietTailExclusionSeconds
        self.minConfidence = minConfidence
    }
}

/// Detects individual chassis impacts from `ProcessedSample` frames.
///
/// State machine: idle → inImpact (accumulate peak) → emit on decay or end → debounce.
public final class TapDetector: @unchecked Sendable {
    public private(set) var config: TapDetectorConfig

    private enum State {
        case idle
        case inImpact
    }

    private var state: State = .idle
    private var impactStart: TimeInterval = 0
    private var peakFiltered = 0.0
    private var peakLinear = 0.0
    private var peakJerk = 0.0
    private var entryThreshold = 0.0
    private var lastAcceptedTime: TimeInterval = -.infinity
    private var previousLinearMagnitude: Double?
    private var previousTimestamp: TimeInterval?
    private var firstTimestamp: TimeInterval?
    private var linearHistory: [(t: TimeInterval, value: Double)] = []
    private var filteredHistory: [(t: TimeInterval, value: Double)] = []

    public init(config: TapDetectorConfig = TapDetectorConfig()) {
        self.config = config
    }

    public func reset() {
        state = .idle
        impactStart = 0
        peakFiltered = 0
        peakLinear = 0
        peakJerk = 0
        entryThreshold = 0
        lastAcceptedTime = -.infinity
        previousLinearMagnitude = nil
        previousTimestamp = nil
        firstTimestamp = nil
        linearHistory.removeAll()
        filteredHistory.removeAll()
    }

    public func updateConfig(_ config: TapDetectorConfig) {
        self.config = config
        reset()
    }

    /// Ingest one processed frame. Returns a `TapEvent` when an impact is completed and accepted.
    public func process(_ sample: ProcessedSample) -> TapEvent? {
        if firstTimestamp == nil {
            firstTimestamp = sample.timestamp
        }

        let jerk = estimateJerk(linearMagnitude: sample.linearMagnitude, timestamp: sample.timestamp)
        appendLinearHistory(timestamp: sample.timestamp, value: sample.linearMagnitude)
        appendFilteredHistory(timestamp: sample.timestamp, value: sample.filteredMagnitude)

        let warmedUp: Bool = {
            guard let firstTimestamp else { return false }
            return sample.timestamp - firstTimestamp >= config.warmupSeconds
        }()

        let adaptive = sample.noiseFloor + config.thresholdSigma * sample.noiseDeviation
        let threshold = max(config.minAbsoluteThresholdG, adaptive)

        var emitted: TapEvent?

        switch state {
        case .idle:
            guard warmedUp else { break }
            guard sample.timestamp - lastAcceptedTime >= config.debounceSeconds else { break }
            guard sample.filteredMagnitude >= threshold else { break }
            // Sustained motion is checked on the *pre-impact* window only.
            guard !isSustainedMotion(before: sample.timestamp, excludingFrom: sample.timestamp) else { break }
            guard isPreImpactQuiet(at: sample.timestamp, threshold: threshold) else { break }

            state = .inImpact
            impactStart = sample.timestamp
            peakFiltered = sample.filteredMagnitude
            peakLinear = sample.linearMagnitude
            // Include rising-edge jerk from just before the threshold crossing.
            peakJerk = max(jerk, recentPeakJerk(before: sample.timestamp, lookback: 0.025))
            entryThreshold = threshold

        case .inImpact:
            peakFiltered = max(peakFiltered, sample.filteredMagnitude)
            peakLinear = max(peakLinear, sample.linearMagnitude)
            peakJerk = max(peakJerk, jerk)

            let elapsed = sample.timestamp - impactStart
            let decayed = sample.filteredMagnitude <= max(entryThreshold, peakFiltered * config.decayFraction)
            let timedOut = elapsed >= config.maxImpactDurationSeconds

            if decayed || timedOut {
                emitted = finalizeImpact(
                    endTime: sample.timestamp,
                    timedOutWithoutDecay: timedOut && !decayed
                )
                state = .idle
            }
        }

        previousLinearMagnitude = sample.linearMagnitude
        previousTimestamp = sample.timestamp
        return emitted
    }

    // MARK: - Internals

    private func estimateJerk(linearMagnitude: Double, timestamp: TimeInterval) -> Double {
        guard let previousLinearMagnitude, let previousTimestamp else {
            return 0
        }
        let dt = timestamp - previousTimestamp
        guard dt > 1e-6 else { return 0 }
        return abs(linearMagnitude - previousLinearMagnitude) / dt
    }

    private func appendLinearHistory(timestamp: TimeInterval, value: Double) {
        linearHistory.append((timestamp, value))
        let cutoff = timestamp - max(config.sustainedMotionWindowSeconds, config.preImpactQuietSeconds)
        linearHistory.removeAll { $0.t < cutoff }
    }

    private func appendFilteredHistory(timestamp: TimeInterval, value: Double) {
        filteredHistory.append((timestamp, value))
        let cutoff = timestamp - max(config.sustainedMotionWindowSeconds, config.preImpactQuietSeconds)
        filteredHistory.removeAll { $0.t < cutoff }
    }

    private func isSustainedMotion(before timestamp: TimeInterval, excludingFrom: TimeInterval) -> Bool {
        let windowStart = timestamp - config.sustainedMotionWindowSeconds
        // Important: do not include the impact samples themselves — a real tap's
        // linear peak (~0.08–0.10 g for light chassis hits) would otherwise look
        // like "sustained motion" and be rejected.
        let window = linearHistory.filter { $0.t >= windowStart && $0.t < excludingFrom }
        guard window.count >= 5 else { return false }
        let mean = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
        return mean >= config.sustainedMotionLimitG
    }

    private func recentPeakJerk(before timestamp: TimeInterval, lookback: TimeInterval) -> Double {
        let start = timestamp - lookback
        let slice = linearHistory.filter { $0.t >= start && $0.t <= timestamp }
        guard slice.count >= 2 else { return 0 }
        var peak = 0.0
        for index in 1..<slice.count {
            let dt = slice[index].t - slice[index - 1].t
            guard dt > 1e-6 else { continue }
            peak = max(peak, abs(slice[index].value - slice[index - 1].value) / dt)
        }
        return peak
    }

    /// True when samples before the rising edge were quiet.
    /// Excludes a short tail so the tap onset itself is not treated as prior noise.
    private func isPreImpactQuiet(at timestamp: TimeInterval, threshold: Double) -> Bool {
        let quietStart = timestamp - config.preImpactQuietSeconds
        let quietEnd = timestamp - config.preImpactQuietTailExclusionSeconds
        guard quietEnd > quietStart else { return true }

        let prior = filteredHistory.filter { $0.t >= quietStart && $0.t < quietEnd }
        guard !prior.isEmpty else { return true }

        let maxPrior = prior.map(\.value).max() ?? 0
        let avgPrior = prior.reduce(0.0) { $0 + $1.value } / Double(prior.count)
        // Allow a little pre-ring; reject only if the earlier window is already hot.
        return maxPrior < threshold * 0.90 && avgPrior < threshold * 0.45
    }

    private func finalizeImpact(endTime: TimeInterval, timedOutWithoutDecay: Bool) -> TapEvent? {
        let duration = max(0, endTime - impactStart)

        // Long plateau without a clean decay ⇒ movement / desk vibration, not a tap.
        if timedOutWithoutDecay {
            return nil
        }
        if duration > config.maxImpactDurationSeconds * 1.25 {
            return nil
        }

        // Recompute rising-edge jerk over the impact neighborhood.
        peakJerk = max(peakJerk, recentPeakJerk(before: endTime, lookback: duration + 0.03))

        let hardHit = peakLinear >= config.hardLinearAmplitudeG
        let impulsive = peakFiltered >= entryThreshold && peakJerk >= config.minJerkGPerSecond

        guard hardHit || impulsive else {
            // Amplitude without jerk (and not a hard hit) — typical of typing chassis rock.
            return nil
        }

        var reasons: [String] = []
        if impulsive { reasons.append("impulse") }
        if hardHit { reasons.append("hardAmplitude") }
        if peakJerk >= config.minJerkGPerSecond { reasons.append("jerk") }

        let confidence = computeConfidence(
            peakFiltered: peakFiltered,
            peakJerk: peakJerk,
            duration: duration,
            threshold: entryThreshold
        )
        guard confidence >= config.minConfidence else { return nil }

        lastAcceptedTime = endTime

        return TapEvent(
            timestamp: impactStart,
            peakStrength: peakFiltered,
            peakLinearMagnitude: peakLinear,
            peakJerk: peakJerk,
            duration: duration,
            confidence: confidence,
            reasons: reasons
        )
    }

    private func computeConfidence(
        peakFiltered: Double,
        peakJerk: Double,
        duration: TimeInterval,
        threshold: Double
    ) -> Double {
        // Strength: how far the peak cleared the entry threshold.
        let strength = min(1.0, max(0.0, (peakFiltered - threshold) / max(threshold, 1e-6) / 4.0))
        // Sharpness: jerk relative to the configured minimum.
        let sharpness = min(1.0, peakJerk / max(config.minJerkGPerSecond * 3.0, 1e-6))
        // Brevity: prefer short impulses; full score at ≤ half max duration.
        let brevity = min(1.0, max(0.0, 1.0 - (duration / max(config.maxImpactDurationSeconds, 1e-6))))

        let score = 0.45 * strength + 0.35 * sharpness + 0.20 * brevity
        return min(1.0, max(0.0, score))
    }
}

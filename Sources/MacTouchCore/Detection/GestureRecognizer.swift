import Foundation

/// Grouped chassis-tap gesture (single / double / triple).
public enum TapGestureKind: Int, Equatable, Sendable, CaseIterable {
    case single = 1
    case double = 2
    case triple = 3

    public var title: String {
        switch self {
        case .single: "single"
        case .double: "double"
        case .triple: "triple"
        }
    }
}

public struct TapGestureEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: TapGestureKind
    /// Timestamp of the first tap in the group.
    public let timestamp: TimeInterval
    /// Timestamp when the gesture was finalized (after grouping window silence).
    public let finalizedAt: TimeInterval
    public let tapCount: Int
    /// Strongest peak among member taps.
    public let peakStrength: Double
    /// Mean confidence of member taps.
    public let confidence: Double
    public let memberTaps: [TapEvent]

    public init(
        id: UUID = UUID(),
        kind: TapGestureKind,
        timestamp: TimeInterval,
        finalizedAt: TimeInterval,
        tapCount: Int,
        peakStrength: Double,
        confidence: Double,
        memberTaps: [TapEvent]
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.finalizedAt = finalizedAt
        self.tapCount = tapCount
        self.peakStrength = peakStrength
        self.confidence = confidence
        self.memberTaps = memberTaps
    }
}

/// Gesture grouping parameters.
///
/// Timing tradeoff: a single tap cannot be reported until `groupingWindow` of silence
/// passes, otherwise a second tap might turn it into a double. Shorter window ⇒ snappier
/// singles, more misclassified doubles. Longer window ⇒ reliable doubles/triples, laggy singles.
public struct GestureRecognizerConfig: Equatable, Sendable {
    /// Max gap between taps that still belong to one gesture sequence.
    public var groupingWindow: TimeInterval

    /// Minimum idle time after a finalized gesture before a new sequence may start.
    public var cooldown: TimeInterval

    /// Cap recognized multiplicity (4+ taps still report as triple).
    public var maxTapsInGesture: Int

    public init(
        groupingWindow: TimeInterval = 0.40,
        cooldown: TimeInterval = 0.20,
        maxTapsInGesture: Int = 3
    ) {
        self.groupingWindow = groupingWindow
        self.cooldown = cooldown
        self.maxTapsInGesture = max(1, maxTapsInGesture)
    }
}

/// Groups `TapEvent`s into single / double / triple gestures.
public final class GestureRecognizer: @unchecked Sendable {
    public private(set) var config: GestureRecognizerConfig

    private var pending: [TapEvent] = []
    private var lastFinalizedAt: TimeInterval = -.infinity

    public init(config: GestureRecognizerConfig = GestureRecognizerConfig()) {
        self.config = config
    }

    public func reset() {
        pending.removeAll()
        lastFinalizedAt = -.infinity
    }

    public func updateConfig(_ config: GestureRecognizerConfig) {
        self.config = config
        reset()
    }

    /// Ingest a newly detected tap. Usually returns `nil` until the grouping window elapses.
    @discardableResult
    public func process(tap: TapEvent) -> TapGestureEvent? {
        // Still in post-gesture cooldown: ignore taps (avoids chatter after a triple).
        if tap.timestamp - lastFinalizedAt < config.cooldown {
            return nil
        }

        if let last = pending.last, tap.timestamp - last.timestamp > config.groupingWindow {
            // A stale open sequence should already have been flushed by `poll(now:)`.
            // If not, finalize it before starting a new one.
            let flushed = finalizePending(at: last.timestamp + config.groupingWindow)
            pending = [tap]
            return flushed
        }

        pending.append(tap)
        return nil
    }

    /// Call on each sensor/sample clock tick so pending singles finalize after silence.
    public func poll(now: TimeInterval) -> TapGestureEvent? {
        guard let last = pending.last else { return nil }
        guard now - last.timestamp >= config.groupingWindow else { return nil }
        return finalizePending(at: now)
    }

    /// Force-finalize any open sequence (end of recording / shutdown).
    public func flush() -> TapGestureEvent? {
        guard let last = pending.last else { return nil }
        return finalizePending(at: last.timestamp + config.groupingWindow)
    }

    private func finalizePending(at finalizedAt: TimeInterval) -> TapGestureEvent? {
        guard !pending.isEmpty else { return nil }

        let taps = pending
        pending.removeAll()

        let count = min(taps.count, config.maxTapsInGesture)
        guard let kind = TapGestureKind(rawValue: count) else { return nil }

        let peak = taps.map(\.peakStrength).max() ?? 0
        let confidence = taps.map(\.confidence).reduce(0, +) / Double(taps.count)
        lastFinalizedAt = finalizedAt

        return TapGestureEvent(
            kind: kind,
            timestamp: taps[0].timestamp,
            finalizedAt: finalizedAt,
            tapCount: count,
            peakStrength: peak,
            confidence: confidence,
            memberTaps: taps
        )
    }
}

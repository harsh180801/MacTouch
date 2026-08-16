import Foundation
import Testing
@testable import MacTouchCore

struct GestureRecognizerTests {
    private func tap(at t: TimeInterval, peak: Double = 0.06, confidence: Double = 0.6) -> TapEvent {
        TapEvent(
            timestamp: t,
            peakStrength: peak,
            peakLinearMagnitude: peak,
            peakJerk: 20,
            duration: 0.02,
            confidence: confidence,
            reasons: ["impulse"]
        )
    }

    @Test func singleTapEmitsAfterGroupingWindow() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.40, cooldown: 0.10)
        )

        #expect(recognizer.process(tap: tap(at: 1.0)) == nil)
        #expect(recognizer.poll(now: 1.20) == nil) // still inside window
        let gesture = recognizer.poll(now: 1.41)
        #expect(gesture?.kind == .single)
        #expect(gesture?.tapCount == 1)
        #expect(gesture?.timestamp == 1.0)
    }

    @Test func doubleTapGroupsTwoImpacts() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.40, cooldown: 0.10)
        )

        #expect(recognizer.process(tap: tap(at: 1.0)) == nil)
        #expect(recognizer.process(tap: tap(at: 1.25)) == nil)
        let gesture = recognizer.poll(now: 1.66)
        #expect(gesture?.kind == .double)
        #expect(gesture?.tapCount == 2)
        #expect(gesture?.memberTaps.count == 2)
    }

    @Test func tripleTapGroupsThreeImpacts() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.40, cooldown: 0.10)
        )

        #expect(recognizer.process(tap: tap(at: 1.0)) == nil)
        #expect(recognizer.process(tap: tap(at: 1.20)) == nil)
        #expect(recognizer.process(tap: tap(at: 1.35)) == nil)
        let gesture = recognizer.poll(now: 1.76)
        #expect(gesture?.kind == .triple)
        #expect(gesture?.tapCount == 3)
    }

    @Test func fourTapsStillReportAsTriple() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.40, cooldown: 0.05, maxTapsInGesture: 3)
        )

        for t in [1.0, 1.15, 1.30, 1.45] {
            _ = recognizer.process(tap: tap(at: t))
        }
        let gesture = recognizer.poll(now: 1.90)
        #expect(gesture?.kind == .triple)
        #expect(gesture?.tapCount == 3)
        #expect(gesture?.memberTaps.count == 4)
    }

    @Test func cooldownIgnoresTapsImmediatelyAfterGesture() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.30, cooldown: 0.50)
        )

        _ = recognizer.process(tap: tap(at: 1.0))
        let first = recognizer.poll(now: 1.31)
        #expect(first?.kind == .single)

        // Inside cooldown — ignored.
        #expect(recognizer.process(tap: tap(at: 1.40)) == nil)
        #expect(recognizer.poll(now: 1.80) == nil)

        // After cooldown — new single.
        #expect(recognizer.process(tap: tap(at: 1.90)) == nil)
        let second = recognizer.poll(now: 2.21)
        #expect(second?.kind == .single)
    }

    @Test func wideGapStartsNewGestureInsteadOfExtendingOldOne() {
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: 0.30, cooldown: 0.05)
        )

        _ = recognizer.process(tap: tap(at: 1.0))
        // Second tap arrives after the window without an intervening poll flush.
        let flushed = recognizer.process(tap: tap(at: 1.50))
        #expect(flushed?.kind == .single)
        #expect(flushed?.timestamp == 1.0)

        let second = recognizer.poll(now: 1.81)
        #expect(second?.kind == .single)
        #expect(second?.timestamp == 1.50)
    }

    @Test func documentsSingleTapLatencyTradeoff() {
        // With a 400 ms grouping window, a lone tap is finalized ~400 ms after impact.
        let window: TimeInterval = 0.40
        let recognizer = GestureRecognizer(
            config: GestureRecognizerConfig(groupingWindow: window, cooldown: 0.1)
        )
        let impact: TimeInterval = 2.0
        _ = recognizer.process(tap: tap(at: impact))
        // Add a tiny epsilon so floating-point (impact + window) still clears `>= window`.
        let gesture = recognizer.poll(now: impact + window + 1e-9)
        #expect(gesture?.kind == .single)
        #expect(gesture != nil)
        if let gesture {
            #expect(abs(gesture.finalizedAt - (impact + window)) < 1e-6)
        }
    }
}

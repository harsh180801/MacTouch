import Foundation
import MacTouchCore

/// Owns the live HID → gesture pipeline for the menu-bar app.
final class ListeningEngine: @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case listening
        case deviceMissing
        case failed(String)
    }

    private let sensor = SensorService()
    private let lock = NSLock()
    private var processor = SignalProcessor()
    private var detector = TapDetector()
    private var gestures = GestureRecognizer()
    private var running = false

    var onGesture: (@Sendable (TapGestureEvent) -> Void)?
    var onStatus: (@Sendable (Status) -> Void)?
    var onFilteredMagnitude: (@Sendable (Double) -> Void)?

    var isAvailable: Bool { sensor.isAvailable() }

    func apply(settings: MacTouchSettings) {
        lock.lock()
        defer { lock.unlock() }
        var tap = TapDetectorConfig()
        var gesture = GestureRecognizerConfig()
        settings.apply(to: &tap)
        settings.apply(to: &gesture)
        detector.updateConfig(tap)
        gestures.updateConfig(gesture)
        processor.reset()
    }

    func start(settings: MacTouchSettings) {
        lock.lock()
        let alreadyRunning = running
        lock.unlock()
        guard !alreadyRunning else { return }

        guard sensor.isAvailable() else {
            onStatus?(.deviceMissing)
            return
        }

        apply(settings: settings)

        sensor.onSample = { [weak self] sample in
            self?.ingest(sample)
        }

        do {
            try sensor.start()
            lock.lock()
            running = true
            lock.unlock()
            onStatus?(.listening)
        } catch {
            onStatus?(.failed(error.localizedDescription))
        }
    }

    func stop() {
        sensor.stop()
        let flushed: TapGestureEvent?
        lock.lock()
        running = false
        flushed = gestures.flush()
        lock.unlock()
        if let flushed {
            onGesture?(flushed)
        }
        onStatus?(.idle)
    }

    private func ingest(_ sample: SensorSample) {
        var emitted: [TapGestureEvent] = []
        var filteredMagnitude: Double?

        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        let processed = processor.process(sample)
        filteredMagnitude = processed.filteredMagnitude
        if let tap = detector.process(processed) {
            if let flushed = gestures.process(tap: tap) {
                emitted.append(flushed)
            }
        }
        if let gesture = gestures.poll(now: sample.timestamp) {
            emitted.append(gesture)
        }
        lock.unlock()

        for gesture in emitted {
            onGesture?(gesture)
        }
        if let filteredMagnitude {
            onFilteredMagnitude?(filteredMagnitude)
        }
    }
}

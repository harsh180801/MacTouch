import Foundation

/// Replays a `SensorRecording` without opening the physical HID device.
///
/// Use this for offline algorithm development and tests. No root privileges needed.
public final class SensorReplayer: @unchecked Sendable {
    public enum Mode: Sendable {
        /// Deliver every sample as fast as the consumer can take them (unit tests).
        case immediate
        /// Sleep between samples using recorded timestamp deltas (wall-clock replay).
        case realtime
    }

    public var onSample: (@Sendable (SensorSample) -> Void)?

    private let recording: SensorRecording
    private let mode: Mode
    private let queue = DispatchQueue(label: "com.mactouch.replayer")
    private var isRunning = false
    private let stateLock = NSLock()

    public init(recording: SensorRecording, mode: Mode = .immediate) {
        self.recording = recording
        self.mode = mode
    }

    public convenience init(url: URL, mode: Mode = .immediate) throws {
        let recording = try SensorRecordingIO.read(from: url)
        self.init(recording: recording, mode: mode)
    }

    public var sampleCount: Int { recording.sampleCount }

    public var durationSeconds: TimeInterval { recording.durationSeconds }

    /// Synchronously emit all samples on the calling thread (immediate mode only).
    public func playAllSynchronously() {
        for sample in recording.samples {
            onSample?(sample)
        }
    }

    /// Start asynchronous replay. Returns immediately; samples arrive on a background queue.
    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return }
        guard !recording.samples.isEmpty else {
            throw SensorRecordingIO.Error.emptyRecording
        }
        isRunning = true

        let samples = recording.samples
        let mode = self.mode
        queue.async { [weak self] in
            guard let self else { return }
            var previousTimestamp: TimeInterval?
            for sample in samples {
                self.stateLock.lock()
                let running = self.isRunning
                self.stateLock.unlock()
                guard running else { break }

                if mode == .realtime, let previousTimestamp {
                    let delay = max(0, sample.timestamp - previousTimestamp)
                    if delay > 0 {
                        Thread.sleep(forTimeInterval: delay)
                    }
                }
                previousTimestamp = sample.timestamp
                self.onSample?(sample)
            }

            self.stateLock.lock()
            self.isRunning = false
            self.stateLock.unlock()
        }
    }

    public func stop() {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
    }

    public var running: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }
}

import Darwin
import Foundation
import MacTouchCore

/// CLI for live capture, record/replay, signal preview, and tap detection.
///
/// Privilege policy: live capture runs as the current user. Replay never needs elevation.
@main
enum MacTouchProbe {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            exit(0)
        }

        let duration = parseDouble(arguments, flag: "--duration") ?? 8.0
        let printEvery = parseInt(arguments, flag: "--every") ?? 1
        let recordURL = parsePath(arguments, flag: "--record")
        let replayURL = parsePath(arguments, flag: "--replay")
        let notes = parseString(arguments, flag: "--notes") ?? ""
        let realtimeReplay = arguments.contains("--realtime")
        let showProcessed = arguments.contains("--process")
        let recognizeGestures = arguments.contains("--gestures")
        // Gesture mode requires tap detection underneath.
        let detectTaps = arguments.contains("--detect") || recognizeGestures
        let groupingWindow = parseDouble(arguments, flag: "--grouping") ?? 0.40
        let gestureCooldown = parseDouble(arguments, flag: "--gesture-cooldown") ?? 0.20

        if recordURL != nil && replayURL != nil {
            fputs("ERROR: use either --record or --replay, not both.\n", stderr)
            exit(64)
        }

        let options = ProbeOptions(
            duration: duration,
            printEvery: printEvery,
            recordURL: recordURL,
            notes: notes,
            realtimeReplay: realtimeReplay,
            showProcessed: showProcessed,
            detectTaps: detectTaps,
            recognizeGestures: recognizeGestures,
            groupingWindow: groupingWindow,
            gestureCooldown: gestureCooldown
        )

        if let replayURL {
            runReplay(url: replayURL, options: options)
        } else {
            runLive(options: options)
        }
    }

    private struct ProbeOptions {
        var duration: TimeInterval
        var printEvery: Int
        var recordURL: URL?
        var notes: String
        var realtimeReplay: Bool
        var showProcessed: Bool
        var detectTaps: Bool
        var recognizeGestures: Bool
        var groupingWindow: TimeInterval
        var gestureCooldown: TimeInterval
    }

    // MARK: - Live / record

    private static func runLive(options: ProbeOptions) {
        let service = SensorService()

        fputs("MacTouchProbe — live sensor capture (non-root)\n", stderr)
        fputs("Looking for AppleSPUHIDDevice accel (page 0xFF00, usage 3)…\n", stderr)

        guard service.isAvailable() else {
            fputs(
                """
                ERROR: Accelerometer HID device not found.
                This Mac may lack AppleSPUHIDDevice, or the IMU endpoint is missing.
                Compatible class: Apple Silicon MacBook Pro / Air with SPU IMU.
                """,
                stderr
            )
            exit(2)
        }

        fputs("Device present. Opening as current user (euid=\(geteuid()))…\n", stderr)

        let counter = SampleCounter()
        let collector = SampleCollector()
        let pipeline = SamplePipeline(
            showProcessed: options.showProcessed,
            detectTaps: options.detectTaps,
            recognizeGestures: options.recognizeGestures,
            groupingWindow: options.groupingWindow,
            gestureCooldown: options.gestureCooldown
        )

        service.onSample = { sample in
            collector.append(sample)
            let count = counter.increment()
            pipeline.ingest(sample, printSampleLine: count % options.printEvery == 0)
            if count % options.printEvery == 0 {
                counter.markPrinted(count)
            }
        }

        do {
            try service.start()
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            fputs(
                """
                Next steps (no automatic elevation):
                1. System Settings → Privacy & Security → Input Monitoring — allow Terminal/Cursor if prompted.
                2. Re-run this probe.
                3. Only if open/stream still fails, we can discuss a privileged helper later.
                """,
                stderr
            )
            exit(1)
        }

        if let recordURL = options.recordURL {
            fputs("Recording to \(recordURL.path)\n", stderr)
        }
        if options.showProcessed {
            fputs("Signal processing preview enabled (--process).\n", stderr)
        }
        if options.detectTaps {
            fputs("Tap detection enabled (--detect).\n", stderr)
        }
        if options.recognizeGestures {
            fputs(
                "Gesture recognition enabled (--gestures). grouping=\(String(format: "%.2f", options.groupingWindow))s cooldown=\(String(format: "%.2f", options.gestureCooldown))s\n",
                stderr
            )
            fputs(
                "Note: single taps are delayed by the grouping window to distinguish doubles/triples.\n",
                stderr
            )
        }

        fputs(
            """
            Streaming for \(String(format: "%.1f", options.duration))s (Ctrl+C to stop early).
            Light taps on the aluminum chassis are fine; do not strike the display.
            Printing 1 of every \(options.printEvery) sample(s).

            """,
            stderr
        )

        let runLoop = RunLoop.current
        let endDate = Date().addingTimeInterval(options.duration)
        while Date() < endDate, runLoop.run(mode: .default, before: Date().addingTimeInterval(0.05)) {
        }

        service.stop()
        pipeline.flush(groupingWindow: options.groupingWindow)

        let totals = counter.snapshot
        let collected = collector.samples

        if totals.total == 0 {
            fputs(
                """
                ERROR: Device opened but zero samples arrived.
                The SPU driver may still be asleep, blocked by permissions, or not streaming.
                Do not use sudo yet — report this result and we will diagnose next.
                """,
                stderr
            )
            exit(3)
        }

        if let recordURL = options.recordURL {
            do {
                let recording = SensorRecording.fromLiveSamples(collected, notes: options.notes)
                try SensorRecordingIO.write(recording, to: recordURL)
                fputs(
                    "Wrote \(recording.sampleCount) samples (\(String(format: "%.2f", recording.durationSeconds))s) → \(recordURL.path)\n",
                    stderr
                )
            } catch {
                fputs("ERROR writing recording: \(error.localizedDescription)\n", stderr)
                exit(4)
            }
        }

        printPipelineSummary(pipeline, options: options)

        let printedApprox = totals.lastPrinted / max(options.printEvery, 1)
        fputs(
            "Done. samples=\(totals.total) printed≈\(printedApprox) rate≈\(String(format: "%.0f", Double(totals.total) / options.duration)) Hz\n",
            stderr
        )
        exit(0)
    }

    // MARK: - Replay

    private static func runReplay(url: URL, options: ProbeOptions) {
        fputs("MacTouchProbe — offline replay (no HID / no elevation)\n", stderr)

        let recording: SensorRecording
        do {
            recording = try SensorRecordingIO.read(from: url)
        } catch {
            fputs("ERROR reading \(url.path): \(error.localizedDescription)\n", stderr)
            exit(5)
        }

        guard !recording.samples.isEmpty else {
            fputs("ERROR: recording is empty.\n", stderr)
            exit(3)
        }

        fputs(
            """
            Loaded \(recording.sampleCount) samples, duration \(String(format: "%.3f", recording.durationSeconds))s
            source=\(recording.source) notes=\(recording.notes.isEmpty ? "(none)" : recording.notes)
            mode=\(options.realtimeReplay ? "realtime" : "immediate") every=\(options.printEvery) process=\(options.showProcessed) detect=\(options.detectTaps) gestures=\(options.recognizeGestures)

            """,
            stderr
        )

        let counter = SampleCounter()
        let pipeline = SamplePipeline(
            showProcessed: options.showProcessed,
            detectTaps: options.detectTaps,
            recognizeGestures: options.recognizeGestures,
            groupingWindow: options.groupingWindow,
            gestureCooldown: options.gestureCooldown
        )
        let replayer = SensorReplayer(
            recording: recording,
            mode: options.realtimeReplay ? .realtime : .immediate
        )

        let handle: @Sendable (SensorSample) -> Void = { sample in
            let count = counter.increment()
            pipeline.ingest(sample, printSampleLine: count % options.printEvery == 0)
            if count % options.printEvery == 0 {
                counter.markPrinted(count)
            }
        }

        if options.realtimeReplay {
            let done = DispatchSemaphore(value: 0)
            replayer.onSample = { sample in
                handle(sample)
                if counter.snapshot.total >= recording.sampleCount {
                    done.signal()
                }
            }
            do {
                try replayer.start()
            } catch {
                fputs("ERROR: \(error.localizedDescription)\n", stderr)
                exit(5)
            }
            let timeout = recording.durationSeconds + 5
            if done.wait(timeout: .now() + timeout) == .timedOut {
                replayer.stop()
                fputs("ERROR: realtime replay timed out.\n", stderr)
                exit(6)
            }
        } else {
            replayer.onSample = handle
            replayer.playAllSynchronously()
        }

        let totals = counter.snapshot
        pipeline.flush(groupingWindow: options.groupingWindow)
        printPipelineSummary(pipeline, options: options)
        fputs("Replay done. samples=\(totals.total)\n", stderr)
        exit(0)
    }

    private static func printPipelineSummary(_ pipeline: SamplePipeline, options: ProbeOptions) {
        if options.detectTaps {
            fputs("Tap events detected: \(pipeline.tapCount)\n", stderr)
        }
        if options.recognizeGestures {
            let c = pipeline.gestureCounts
            fputs(
                "Gestures: single=\(c.single) double=\(c.double) triple=\(c.triple) total=\(c.single + c.double + c.triple)\n",
                stderr
            )
        }
    }

    // MARK: - CLI helpers

    private static func printUsage() {
        let text = """
        MacTouchProbe — accelerometer probe, record, replay, process, detect, gestures

        Live:
          swift run MacTouchProbe [--duration 8] [--every 40]
          swift run MacTouchProbe --detect --duration 8 --every 100
          swift run MacTouchProbe --gestures --duration 12 --every 100
          swift run MacTouchProbe --gestures --grouping 0.35 --gesture-cooldown 0.25

        Replay:
          swift run MacTouchProbe --replay Recordings/taps.csv --gestures

        Options:
          --duration <sec>          Live capture length (default 8)
          --every <n>               Print 1 of every n samples (default 1)
          --record <path>           Write .csv or .json after capture
          --replay <path>           Play a recording instead of opening HID
          --realtime                Pace replay using recorded timestamps
          --process                 Print filtered signal (raw/lin/filt/floor/norm)
          --detect                  Run tap detector; print TAP events
          --gestures                Group taps into single/double/triple (implies detect)
          --grouping <sec>          Gesture grouping window (default 0.40)
          --gesture-cooldown <sec>  Idle after a gesture (default 0.20)
          --notes <text>            Optional note stored in the recording metadata
          -h, --help                Show this help

        Timing tradeoff:
          Single-tap actions wait up to --grouping seconds to see if more taps arrive.
          Shorter window = snappier singles, more double/triple mistakes.
          Longer window = reliable multi-taps, laggy singles.
        """
        fputs(text + "\n", stdout)
    }

    private static func parseDouble(_ args: [String], flag: String) -> Double? {
        guard let index = args.firstIndex(of: flag),
              args.index(after: index) < args.endIndex,
              let value = Double(args[args.index(after: index)]),
              value > 0 else { return nil }
        return value
    }

    private static func parseInt(_ args: [String], flag: String) -> Int? {
        guard let index = args.firstIndex(of: flag),
              args.index(after: index) < args.endIndex,
              let value = Int(args[args.index(after: index)]),
              value > 0 else { return nil }
        return value
    }

    private static func parseString(_ args: [String], flag: String) -> String? {
        guard let index = args.firstIndex(of: flag),
              args.index(after: index) < args.endIndex else { return nil }
        return args[args.index(after: index)]
    }

    private static func parsePath(_ args: [String], flag: String) -> URL? {
        guard let value = parseString(args, flag: flag) else { return nil }
        return URL(fileURLWithPath: value)
    }
}

// MARK: - Thread-safe helpers

private final class SampleCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    private var lastPrintedCount = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        total += 1
        return total
    }

    func markPrinted(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        lastPrintedCount = count
    }

    var snapshot: (total: Int, lastPrinted: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (total, lastPrintedCount)
    }
}

private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SensorSample] = []

    func append(_ sample: SensorSample) {
        lock.lock()
        storage.append(sample)
        lock.unlock()
    }

    var samples: [SensorSample] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class SamplePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let showProcessed: Bool
    private let detectTaps: Bool
    private let recognizeGestures: Bool
    private let processor: SignalProcessor?
    private let detector: TapDetector?
    private let gestures: GestureRecognizer?
    private var taps = 0
    private var singles = 0
    private var doubles = 0
    private var triples = 0

    init(
        showProcessed: Bool,
        detectTaps: Bool,
        recognizeGestures: Bool,
        groupingWindow: TimeInterval,
        gestureCooldown: TimeInterval
    ) {
        self.showProcessed = showProcessed
        self.detectTaps = detectTaps
        self.recognizeGestures = recognizeGestures
        let needsProcessor = showProcessed || detectTaps || recognizeGestures
        self.processor = needsProcessor ? SignalProcessor() : nil
        self.detector = (detectTaps || recognizeGestures) ? TapDetector() : nil
        self.gestures = recognizeGestures
            ? GestureRecognizer(
                config: GestureRecognizerConfig(
                    groupingWindow: groupingWindow,
                    cooldown: gestureCooldown
                )
            )
            : nil
    }

    var tapCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return taps
    }

    var gestureCounts: (single: Int, double: Int, triple: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (singles, doubles, triples)
    }

    func ingest(_ sample: SensorSample, printSampleLine: Bool) {
        lock.lock()
        defer { lock.unlock() }

        var processed: ProcessedSample?
        if let processor {
            processed = processor.process(sample)
            if let detector, let processed {
                if let event = detector.process(processed) {
                    taps += 1
                    if !recognizeGestures {
                        printTapLine(event)
                    }
                    if let gestures {
                        if let flushed = gestures.process(tap: event) {
                            recordGesture(flushed)
                        }
                    }
                }
            }
            if let gestures {
                if let gesture = gestures.poll(now: sample.timestamp) {
                    recordGesture(gesture)
                }
            }
        }

        guard printSampleLine else { return }

        if showProcessed, let processed {
            printProcessedLine(processed)
        } else if !detectTaps && !recognizeGestures {
            printRawLine(sample)
        }
    }

    private func recordGesture(_ gesture: TapGestureEvent) {
        switch gesture.kind {
        case .single: singles += 1
        case .double: doubles += 1
        case .triple: triples += 1
        }
        printGestureLine(gesture)
    }

    /// Finalize any open gesture after the stream ends (last single would otherwise hang).
    func flush(groupingWindow: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let gestures else { return }
        if let gesture = gestures.flush() {
            recordGesture(gesture)
        }
        _ = groupingWindow
    }
}

private func printRawLine(_ sample: SensorSample) {
    let line = String(
        format: "t=%.6f  x=%+.5f  y=%+.5f  z=%+.5f  mag=%.5f\n",
        sample.timestamp,
        sample.x,
        sample.y,
        sample.z,
        sample.magnitude
    )
    fputs(line, stdout)
    fflush(stdout)
}

private func printProcessedLine(_ sample: ProcessedSample) {
    let line = String(
        format: "t=%.6f  raw=%.5f  lin=%.5f  filt=%.5f  floor=%.5f  norm=%.2f\n",
        sample.timestamp,
        sample.rawMagnitude,
        sample.linearMagnitude,
        sample.filteredMagnitude,
        sample.noiseFloor,
        sample.normalizedExcess
    )
    fputs(line, stdout)
    fflush(stdout)
}

private func printGestureLine(_ gesture: TapGestureEvent) {
    let line = String(
        format: "GESTURE %-6@  taps=%d  t=%.3f  final=%.3f  peak=%.4f  conf=%.2f\n",
        gesture.kind.title as NSString,
        gesture.tapCount,
        gesture.timestamp,
        gesture.finalizedAt,
        gesture.peakStrength,
        gesture.confidence
    )
    fputs(line, stdout)
    fflush(stdout)
}

private func printTapLine(_ event: TapEvent) {
    let reasons = event.reasons.joined(separator: ",")
    let line = String(
        format: "TAP t=%.3f  peak=%.4f  lin=%.4f  jerk=%.1f  dur=%.3f  conf=%.2f  [%@]\n",
        event.timestamp,
        event.peakStrength,
        event.peakLinearMagnitude,
        event.peakJerk,
        event.duration,
        event.confidence,
        reasons as NSString
    )
    fputs(line, stdout)
    fflush(stdout)
}

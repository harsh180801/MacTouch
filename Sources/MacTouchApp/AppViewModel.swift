import Foundation
import MacTouchCore
import Observation

@MainActor
@Observable
final class AppViewModel {
    enum Phase: Equatable {
        case idle
        case listening
        case calibrating
    }

    private let store: SettingsStore
    private let engine = ListeningEngine()

    private(set) var settings: MacTouchSettings
    private(set) var phase: Phase = .idle
    private(set) var statusMessage = "Idle"
    private(set) var singleCount = 0
    private(set) var doubleCount = 0
    private(set) var tripleCount = 0
    private(set) var lastGestureSummary = "—"
    private(set) var errorMessage: String?
    private(set) var calibrationProgress: CalibrationProgress?
    private(set) var showCalibrationSheet = false

    private var calibrationService: CalibrationService?
    private var calibrationSensor: SensorService?
    private var calibrationStarted = false
    private var saveTask: Task<Void, Never>?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.loadOrDefault()
        wireEngine()
    }

    var isListening: Bool { phase == .listening }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard phase != .calibrating else { return }
        errorMessage = nil
        engine.start(settings: settings)
    }

    func stopListening() {
        engine.stop()
        if phase != .calibrating {
            phase = .idle
            statusMessage = "Idle"
        }
    }

    func resetCounters() {
        singleCount = 0
        doubleCount = 0
        tripleCount = 0
        lastGestureSummary = "—"
    }

    func updateThreshold(_ value: Double) {
        settings.minAbsoluteThresholdG = max(0.01, min(value, 1.0))
        scheduleSaveAndMaybeReapply()
    }

    func updateGrouping(_ value: Double) {
        settings.groupingWindow = max(0.15, min(value, 1.0))
        scheduleSaveAndMaybeReapply()
    }

    func updateCooldown(_ value: Double) {
        settings.gestureCooldown = max(0.05, min(value, 1.0))
        scheduleSaveAndMaybeReapply()
    }

    func beginCalibration() {
        errorMessage = nil
        stopListening()
        showCalibrationSheet = true
        phase = .calibrating
        statusMessage = "Calibrating…"
        calibrationStarted = false
        calibrationProgress = nil

        let service = CalibrationService()
        calibrationService = service

        let sensor = SensorService()
        calibrationSensor = sensor
        sensor.onSample = { [weak self] sample in
            Task { @MainActor in
                self?.ingestCalibration(sample)
            }
        }

        do {
            try sensor.start()
        } catch {
            errorMessage = error.localizedDescription
            endCalibrationSession()
        }
    }

    func cancelCalibration() {
        endCalibrationSession()
    }

    private func wireEngine() {
        engine.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.applyEngineStatus(status)
            }
        }
        engine.onGesture = { [weak self] gesture in
            Task { @MainActor in
                self?.record(gesture)
            }
        }
    }

    private func applyEngineStatus(_ status: ListeningEngine.Status) {
        switch status {
        case .idle:
            if phase != .calibrating {
                phase = .idle
                statusMessage = "Idle"
            }
        case .listening:
            phase = .listening
            statusMessage = "Listening"
            errorMessage = nil
        case .deviceMissing:
            phase = .idle
            statusMessage = "Device missing"
            errorMessage = "No AppleSPUHID accelerometer found."
        case .failed(let message):
            phase = .idle
            statusMessage = "Open failed"
            errorMessage = message
        }
    }

    private func record(_ gesture: TapGestureEvent) {
        switch gesture.kind {
        case .single: singleCount += 1
        case .double: doubleCount += 1
        case .triple: tripleCount += 1
        }
        lastGestureSummary =
            "\(gesture.kind.title) · peak \(String(format: "%.3f", gesture.peakStrength)) g"
    }

    private func scheduleSaveAndMaybeReapply() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                try store.save(settings)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            if phase == .listening {
                engine.apply(settings: settings)
            }
        }
    }

    private func ingestCalibration(_ sample: SensorSample) {
        guard phase == .calibrating, let service = calibrationService else { return }

        if !calibrationStarted {
            service.start(at: sample.timestamp)
            calibrationStarted = true
        }

        let progress = service.ingest(sample)
        calibrationProgress = progress

        guard progress.stage == .done else { return }

        do {
            let recommended = try service.finish()
            settings = recommended
            try store.save(recommended)
            endCalibrationSession()
        } catch {
            errorMessage = error.localizedDescription
            endCalibrationSession()
        }
    }

    private func endCalibrationSession() {
        calibrationSensor?.stop()
        calibrationSensor = nil
        calibrationService = nil
        calibrationProgress = nil
        calibrationStarted = false
        showCalibrationSheet = false
        phase = .idle
        statusMessage = "Idle"
    }
}

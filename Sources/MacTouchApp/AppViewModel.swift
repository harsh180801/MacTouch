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
    private let actionStore: ActionSettingsStore
    private let engine = ListeningEngine()
    private let dispatcher: ShortcutActionDispatcher

    private(set) var settings: MacTouchSettings
    private(set) var actionSettings: ActionSettings
    private(set) var phase: Phase = .idle
    private(set) var statusMessage = "Idle"
    private(set) var singleCount = 0
    private(set) var doubleCount = 0
    private(set) var tripleCount = 0
    private(set) var lastGestureSummary = "—"
    private(set) var errorMessage: String?
    private(set) var calibrationProgress: CalibrationProgress?
    private(set) var showCalibrationSheet = false
    private(set) var lastActionStatus = "—"
    private(set) var waveformPoints: [Double] = []

    private var calibrationService: CalibrationService?
    private var calibrationSensor: SensorService?
    private var calibrationStarted = false
    private var saveSettingsTask: Task<Void, Never>?
    private var saveActionsTask: Task<Void, Never>?
    private var waveform = WaveformBuffer(capacity: 96)
    private var waveformSampleCounter = 0
    private var waveformEma: Double = 0
    private var hasWaveformEma = false
    private var waveformPeakReference = 0.03

    init(
        store: SettingsStore = SettingsStore(),
        actionStore: ActionSettingsStore = ActionSettingsStore(),
        dispatcher: ShortcutActionDispatcher = ShortcutActionDispatcher()
    ) {
        self.store = store
        self.actionStore = actionStore
        self.dispatcher = dispatcher
        self.settings = store.loadOrDefault()
        self.actionSettings = actionStore.loadOrDefault()
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
        scheduleSettingsSaveAndMaybeReapply()
    }

    func updateGrouping(_ value: Double) {
        settings.groupingWindow = max(0.15, min(value, 1.0))
        scheduleSettingsSaveAndMaybeReapply()
    }

    func updateCooldown(_ value: Double) {
        settings.gestureCooldown = max(0.05, min(value, 1.0))
        scheduleSettingsSaveAndMaybeReapply()
    }

    func updateActionsEnabled(_ enabled: Bool) {
        actionSettings.enabled = enabled
        scheduleActionSettingsSave()
    }

    func updateActionCooldown(_ value: Double) {
        actionSettings.cooldownSeconds = max(0.5, min(value, 5.0))
        scheduleActionSettingsSave()
    }

    func updateShortcutName(_ value: String, for kind: TapGestureKind) {
        let normalized = ActionSettings.normalizedName(value)
        if normalized != nil {
            actionSettings.setActionKind(.shortcut, for: kind)
        }
        switch kind {
        case .single:
            actionSettings.singleShortcutName = normalized
        case .double:
            actionSettings.doubleShortcutName = normalized
        case .triple:
            actionSettings.tripleShortcutName = normalized
        }
        scheduleActionSettingsSave()
    }

    func updateAppName(_ value: String, for kind: TapGestureKind) {
        let normalized = ActionSettings.normalizedName(value)
        if normalized != nil {
            actionSettings.setActionKind(.launchApp, for: kind)
        }
        switch kind {
        case .single:
            actionSettings.singleAppName = normalized
        case .double:
            actionSettings.doubleAppName = normalized
        case .triple:
            actionSettings.tripleAppName = normalized
        }
        scheduleActionSettingsSave()
    }

    func updateNotificationTitle(_ value: String) {
        actionSettings.notificationTitle = value
        scheduleActionSettingsSave()
    }

    func updateNotificationBody(_ value: String) {
        actionSettings.notificationBody = value
        scheduleActionSettingsSave()
    }

    func actionKind(for kind: TapGestureKind) -> GestureActionKind {
        actionSettings.actionKind(for: kind)
    }

    func updateActionKind(_ value: GestureActionKind, for kind: TapGestureKind) {
        actionSettings.setActionKind(value, for: kind)
        scheduleActionSettingsSave()
    }

    func runShortcutNow(_ kind: TapGestureKind) {
        triggerShortcut(for: kind)
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
        engine.onFilteredMagnitude = { [weak self] value in
            Task { @MainActor in
                self?.recordWaveform(value)
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
        triggerShortcut(for: gesture.kind)
    }

    private func scheduleSettingsSaveAndMaybeReapply() {
        saveSettingsTask?.cancel()
        saveSettingsTask = Task { @MainActor in
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

    private func scheduleActionSettingsSave() {
        saveActionsTask?.cancel()
        saveActionsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                try actionStore.save(actionSettings)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func triggerShortcut(for kind: TapGestureKind) {
        let currentSettings = actionSettings
        Task { [dispatcher, weak self] in
            let outcome = dispatcher.dispatch(gesture: kind, settings: currentSettings)
            await MainActor.run {
                guard let self else { return }
                self.lastActionStatus = outcome.summary
                if case .failed = outcome {
                    self.errorMessage = outcome.summary
                }
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

    private func recordWaveform(_ value: Double) {
        waveformSampleCounter += 1
        // Keep UI smooth in popover by downsampling fast sensor callbacks.
        guard waveformSampleCounter % 8 == 0 else { return }
        let clamped = max(0, value)
        let emaAlpha = 0.33
        if hasWaveformEma {
            waveformEma = (emaAlpha * clamped) + ((1 - emaAlpha) * waveformEma)
        } else {
            waveformEma = clamped
            hasWaveformEma = true
        }

        waveform.append(waveformEma)

        // Hold peaks briefly, then decay reference slowly to prevent jumpy scaling.
        let decayPerSample = 0.987
        waveformPeakReference = max(waveformEma, waveformPeakReference * decayPerSample)
        waveformPoints = waveform.normalized(reference: waveformPeakReference)
    }
}

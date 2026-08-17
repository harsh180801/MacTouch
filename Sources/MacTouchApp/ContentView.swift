import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            counters
            settings
            actions
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 320)
        .sheet(isPresented: Binding(
            get: { model.showCalibrationSheet },
            set: { presented in
                if !presented { model.cancelCalibration() }
            }
        )) {
            CalibrationSheet(model: model)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacTouch")
                    .font(.headline)
                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                model.isListening ? "On" : "Off",
                isOn: Binding(
                    get: { model.isListening },
                    set: { wantOn in
                        if wantOn != model.isListening {
                            model.toggleListening()
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(model.phase == .calibrating)
        }
    }

    private var counters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gestures")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                counter("Single", model.singleCount)
                counter("Double", model.doubleCount)
                counter("Triple", model.tripleCount)
            }
            Text(model.lastGestureSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Reset counters") {
                model.resetCounters()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func counter(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            labeledSlider(
                "Threshold",
                value: model.settings.minAbsoluteThresholdG,
                range: 0.01...0.12,
                format: "%.3f g"
            ) { model.updateThreshold($0) }

            labeledSlider(
                "Grouping",
                value: model.settings.groupingWindow,
                range: 0.20...0.55,
                format: "%.2f s"
            ) { model.updateGrouping($0) }

            labeledSlider(
                "Cooldown",
                value: model.settings.gestureCooldown,
                range: 0.08...0.40,
                format: "%.2f s"
            ) { model.updateCooldown($0) }

            Text("Saved to ~/.config/MacTouch/settings.json")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: String,
        onChange: @escaping @MainActor (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in onChange(newValue) }
                ),
                in: range
            )
        }
    }

    private var actions: some View {
        HStack {
            Button("Calibrate…") {
                model.beginCalibration()
            }
            .disabled(model.phase == .calibrating)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

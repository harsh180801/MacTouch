import AppKit
import MacTouchCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            counters
            settings
            shortcutActions
            footerActions
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

    private var shortcutActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut Actions")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Enable Shortcut Actions",
                isOn: Binding(
                    get: { model.actionSettings.enabled },
                    set: { model.updateActionsEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            shortcutRow(
                title: "Single",
                kind: .single
            )
            shortcutRow(
                title: "Double",
                kind: .double
            )
            shortcutRow(
                title: "Triple",
                kind: .triple
            )

            labeledSlider(
                "Action Cooldown",
                value: model.actionSettings.cooldownSeconds,
                range: 0.5...5.0,
                format: "%.2f s"
            ) { model.updateActionCooldown($0) }

            Text(model.lastActionStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(title: String, kind: TapGestureKind) -> some View {
        let actionKind = model.actionKind(for: kind)
        let currentName = model.actionSettings.shortcutName(for: kind) ?? ""
        return HStack(spacing: 6) {
            Text(title)
                .frame(width: 42, alignment: .leading)
            Picker(
                "",
                selection: Binding(
                    get: { actionKind },
                    set: { model.updateActionKind($0, for: kind) }
                )
            ) {
                Text("None").tag(GestureActionKind.none)
                Text("Shortcut").tag(GestureActionKind.shortcut)
                Text("Mute").tag(GestureActionKind.toggleMute)
            }
            .labelsHidden()
            .frame(width: 94)

            if actionKind == .shortcut {
                TextField(
                    "Shortcut name",
                    text: Binding(
                        get: { currentName },
                        set: { model.updateShortcutName($0, for: kind) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(actionKind == .toggleMute ? "Toggle output mute" : "No action")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Run") {
                model.runShortcutNow(kind)
            }
            .buttonStyle(.bordered)
        }
    }

    private var footerActions: some View {
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

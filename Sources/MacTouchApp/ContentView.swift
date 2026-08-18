import AppKit
import MacTouchCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            waveformPanel
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

    private var waveformPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Signal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(model.isListening ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(model.isListening ? "Live" : "Idle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            WaveformSparkline(values: model.waveformPoints)
                .frame(height: 54)
                .animation(.linear(duration: 0.15), value: model.waveformPoints)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
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

            if model.actionKind(for: .single) == .notify
                || model.actionKind(for: .double) == .notify
                || model.actionKind(for: .triple) == .notify
            {
                TextField(
                    "Notification title",
                    text: Binding(
                        get: { model.actionSettings.notificationTitle },
                        set: { model.updateNotificationTitle($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Notification body",
                    text: Binding(
                        get: { model.actionSettings.notificationBody },
                        set: { model.updateNotificationBody($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

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
                Text("Launch App").tag(GestureActionKind.launchApp)
                Text("Notify").tag(GestureActionKind.notify)
            }
            .labelsHidden()
            .frame(width: 116)

            if actionKind == .shortcut {
                TextField(
                    "Shortcut name",
                    text: Binding(
                        get: { currentName },
                        set: { model.updateShortcutName($0, for: kind) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            } else if actionKind == .launchApp {
                let appName = model.actionSettings.appName(for: kind) ?? ""
                TextField(
                    "App name",
                    text: Binding(
                        get: { appName },
                        set: { model.updateAppName($0, for: kind) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(description(for: actionKind))
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

    private func description(for actionKind: GestureActionKind) -> String {
        switch actionKind {
        case .none:
            return "No action"
        case .toggleMute:
            return "Toggle output mute"
        case .notify:
            return "Show local notification"
        case .shortcut, .launchApp:
            return ""
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

private struct WaveformSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let points = makePoints(width: width, height: height)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))

                if points.count > 1 {
                    fillPath(points: points, height: height)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.34),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    curvePath(points: points)
                        .stroke(Color.accentColor.opacity(0.32), style: StrokeStyle(lineWidth: 4.8, lineCap: .round, lineJoin: .round))
                        .blur(radius: 1.8)

                    curvePath(points: points)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                } else {
                    Text("Waiting for samples…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                        .padding(.bottom, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func makePoints(width: Double, height: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let denominator = Double(max(values.count - 1, 1))
        let verticalInset = max(3.0, height * 0.08)
        return values.enumerated().map { index, value in
            let x = (Double(index) / denominator) * width
            let drawableHeight = max(1, height - (verticalInset * 2))
            let y = verticalInset + max(0, min(drawableHeight, (1.0 - value) * drawableHeight))
            return CGPoint(x: x, y: y)
        }
    }

    private func curvePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    private func fillPath(points: [CGPoint], height: Double) -> Path {
        var path = curvePath(points: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

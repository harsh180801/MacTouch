import MacTouchCore
import SwiftUI

struct CalibrationSheet: View {
    @Bindable var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibration")
                .font(.title2)

            if let progress = model.calibrationProgress {
                Text(progress.prompt)
                    .font(.body)
                progressDetails(progress)
            } else {
                Text("Keep still to begin the idle baseline…")
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelCalibration()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 220)
    }

    private func progressDetails(_ progress: CalibrationProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stage: \(progress.stage.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch progress.stage {
            case .idle:
                Text("Idle samples: \(progress.idleSamples)")
                    .font(.caption.monospacedDigit())
            case .singles:
                Text("Singles: \(progress.singleCount)/\(progress.requiredSingles)")
                    .font(.caption.monospacedDigit())
            case .doubles:
                Text("Double pairs: \(progress.doublePairCount)/\(progress.requiredDoubles)")
                    .font(.caption.monospacedDigit())
            case .done:
                Text("Finishing…")
                    .font(.caption)
            }
        }
    }
}

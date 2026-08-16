import Foundation
import Testing
@testable import MacTouchCore

struct SensorRecordingTests {
    @Test func csvRoundTripPreservesSamples() throws {
        let original = SensorRecording(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: "test",
            notes: "synthetic fixture",
            samples: [
                SensorSample(timestamp: 0.0, x: 0.01, y: -0.25, z: -0.95),
                SensorSample(timestamp: 0.01, x: 0.02, y: -0.24, z: -0.94),
                SensorSample(timestamp: 0.02, x: 0.50, y: -0.10, z: -0.80)
            ]
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try SensorRecordingIO.write(original, to: url)
        let loaded = try SensorRecordingIO.read(from: url)

        #expect(loaded.formatVersion == 1)
        #expect(loaded.source == "test")
        #expect(loaded.notes == "synthetic fixture")
        #expect(loaded.samples.count == 3)
        #expect(abs(loaded.samples[0].x - 0.01) < 1e-8)
        #expect(abs(loaded.samples[2].timestamp - 0.02) < 1e-8)
        #expect(abs(loaded.durationSeconds - 0.02) < 1e-8)
    }

    @Test func jsonRoundTripPreservesSamples() throws {
        let original = SensorRecording(
            source: "test-json",
            notes: "json path",
            samples: [
                SensorSample(timestamp: 0.0, x: 1, y: 0, z: 0),
                SensorSample(timestamp: 1.0, x: 0, y: 1, z: 0)
            ]
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactouch-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try SensorRecordingIO.write(original, to: url)
        let loaded = try SensorRecordingIO.read(from: url)

        #expect(loaded.samples.count == 2)
        #expect(loaded.samples[1].y == 1)
        #expect(loaded.source == "test-json")
    }

    @Test func fromLiveSamplesRebasesTimestamps() {
        let live = [
            SensorSample(timestamp: 100.0, x: 0, y: 0, z: 1),
            SensorSample(timestamp: 100.5, x: 0, y: 0, z: 1)
        ]
        let recording = SensorRecording.fromLiveSamples(live, notes: "rebase")
        #expect(recording.samples[0].timestamp == 0)
        #expect(abs(recording.samples[1].timestamp - 0.5) < 1e-9)
        #expect(abs(recording.durationSeconds - 0.5) < 1e-9)
    }

    @Test func replayerImmediateDeliversAllSamples() {
        let recording = SensorRecording(
            samples: [
                SensorSample(timestamp: 0.0, x: 1, y: 0, z: 0),
                SensorSample(timestamp: 0.1, x: 2, y: 0, z: 0),
                SensorSample(timestamp: 0.2, x: 3, y: 0, z: 0)
            ]
        )
        let replayer = SensorReplayer(recording: recording, mode: .immediate)
        final class Box: @unchecked Sendable {
            var xs: [Double] = []
        }
        let box = Box()
        replayer.onSample = { box.xs.append($0.x) }
        replayer.playAllSynchronously()
        #expect(box.xs == [1, 2, 3])
    }

    @Test func rejectsUnknownExtension() {
        let url = URL(fileURLWithPath: "/tmp/session.xyz")
        #expect(throws: SensorRecordingIO.Error.unsupportedExtension("xyz")) {
            try SensorRecordingIO.format(for: url)
        }
    }

    @Test func malformedCSVThrows() {
        let text = """
        # MacTouchSensorRecording v1
        0.0,1,0,0
        """
        #expect(throws: SensorRecordingIO.Error.self) {
            try SensorRecordingIO.decodeCSV(text)
        }
    }
}

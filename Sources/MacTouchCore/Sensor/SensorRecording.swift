import Foundation

/// Metadata + samples for one accelerometer capture session.
///
/// Timestamps inside `samples` are **relative seconds from the first sample**
/// (first sample is usually `t ≈ 0`). Absolute host clocks are not required for
/// offline detection work and avoid leaking wall-clock session times into fixtures.
public struct SensorRecording: Equatable, Sendable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var source: String
    public var notes: String
    public var samples: [SensorSample]

    public var sampleCount: Int { samples.count }

    public var durationSeconds: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.timestamp - first.timestamp)
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, createdAt, source, notes, samples
    }

    public init(
        formatVersion: Int = SensorRecording.currentFormatVersion,
        createdAt: Date = Date(),
        source: String = "live",
        notes: String = "",
        samples: [SensorSample]
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.source = source
        self.notes = notes
        self.samples = samples
    }

    /// Build a recording from live HID samples, rebasing timestamps to start at zero.
    public static func fromLiveSamples(
        _ liveSamples: [SensorSample],
        notes: String = "",
        createdAt: Date = Date()
    ) -> SensorRecording {
        guard let first = liveSamples.first else {
            return SensorRecording(createdAt: createdAt, source: "live", notes: notes, samples: [])
        }
        let rebased = liveSamples.map { sample in
            SensorSample(
                timestamp: sample.timestamp - first.timestamp,
                x: sample.x,
                y: sample.y,
                z: sample.z
            )
        }
        return SensorRecording(createdAt: createdAt, source: "live", notes: notes, samples: rebased)
    }
}

/// File format helpers for sensor sessions.
public enum SensorRecordingIO {
    public enum Format: String, Sendable {
        case json
        case csv
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case unsupportedExtension(String)
        case emptyRecording
        case malformedCSV(String)
        case unsupportedFormatVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Unsupported recording extension \"\(ext)\". Use .json or .csv."
            case .emptyRecording:
                return "Recording contains no samples."
            case .malformedCSV(let detail):
                return "Malformed CSV recording: \(detail)"
            case .unsupportedFormatVersion(let version):
                return "Unsupported recording formatVersion \(version)."
            }
        }
    }

    public static func format(for url: URL) throws -> Format {
        switch url.pathExtension.lowercased() {
        case "json":
            return .json
        case "csv":
            return .csv
        default:
            throw Error.unsupportedExtension(url.pathExtension)
        }
    }

    public static func write(_ recording: SensorRecording, to url: URL) throws {
        let format = try format(for: url)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recording)
            try data.write(to: url, options: .atomic)
        case .csv:
            let text = encodeCSV(recording)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public static func read(from url: URL) throws -> SensorRecording {
        let format = try format(for: url)
        switch format {
        case .json:
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let recording = try decoder.decode(SensorRecording.self, from: data)
            guard recording.formatVersion == SensorRecording.currentFormatVersion else {
                throw Error.unsupportedFormatVersion(recording.formatVersion)
            }
            return recording
        case .csv:
            let text = try String(contentsOf: url, encoding: .utf8)
            return try decodeCSV(text)
        }
    }

    // MARK: - CSV

    /// CSV layout (human-inspectable, good for git fixtures after privacy review):
    /// ```
    /// # MacTouchSensorRecording v1
    /// # created=<ISO8601>
    /// # source=live
    /// # notes=
    /// t,x,y,z
    /// 0.000000,0.01,-0.26,-0.95
    /// ```
    public static func encodeCSV(_ recording: SensorRecording) -> String {
        var lines: [String] = [
            "# MacTouchSensorRecording v\(recording.formatVersion)",
            "# created=\(iso8601(recording.createdAt))",
            "# source=\(escapeMeta(recording.source))",
            "# notes=\(escapeMeta(recording.notes))",
            "# sampleCount=\(recording.sampleCount)",
            "# durationSeconds=\(String(format: "%.6f", recording.durationSeconds))",
            "t,x,y,z"
        ]
        for sample in recording.samples {
            lines.append(
                String(
                    format: "%.6f,%.8f,%.8f,%.8f",
                    sample.timestamp,
                    sample.x,
                    sample.y,
                    sample.z
                )
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func decodeCSV(_ text: String) throws -> SensorRecording {
        var formatVersion = SensorRecording.currentFormatVersion
        var createdAt = Date()
        var source = "unknown"
        var notes = ""
        var samples: [SensorSample] = []
        var sawHeader = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if body.hasPrefix("MacTouchSensorRecording v"),
                   let version = Int(body.dropFirst("MacTouchSensorRecording v".count)) {
                    formatVersion = version
                } else if body.hasPrefix("created="),
                          let date = parseISO8601(String(body.dropFirst("created=".count))) {
                    createdAt = date
                } else if body.hasPrefix("source=") {
                    source = String(body.dropFirst("source=".count))
                } else if body.hasPrefix("notes=") {
                    notes = String(body.dropFirst("notes=".count))
                }
                continue
            }

            if line == "t,x,y,z" {
                sawHeader = true
                continue
            }

            guard sawHeader else {
                throw Error.malformedCSV("missing t,x,y,z header before data rows")
            }

            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4,
                  let t = Double(parts[0]),
                  let x = Double(parts[1]),
                  let y = Double(parts[2]),
                  let z = Double(parts[3]) else {
                throw Error.malformedCSV("bad data row: \(line)")
            }
            samples.append(SensorSample(timestamp: t, x: x, y: y, z: z))
        }

        guard formatVersion == SensorRecording.currentFormatVersion else {
            throw Error.unsupportedFormatVersion(formatVersion)
        }
        guard sawHeader else {
            throw Error.malformedCSV("missing t,x,y,z header")
        }

        return SensorRecording(
            formatVersion: formatVersion,
            createdAt: createdAt,
            source: source,
            notes: notes,
            samples: samples
        )
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private static func escapeMeta(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

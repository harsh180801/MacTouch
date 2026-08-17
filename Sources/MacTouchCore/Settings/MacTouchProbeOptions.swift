import Foundation

public enum MacTouchProbeOptionsError: Error, Equatable, Sendable {
    case recordAndReplayBothSpecified
    case calibrateWithRecordOrReplay
    case missingValue(forFlag: String)
}

public struct MacTouchProbeOptions: Equatable, Sendable {
    public var duration: TimeInterval
    public var printEvery: Int
    public var recordURL: URL?
    public var replayURL: URL?
    public var notes: String
    public var realtimeReplay: Bool
    public var showProcessed: Bool
    public var detectTaps: Bool
    public var recognizeGestures: Bool
    public var groupingWindow: TimeInterval
    public var gestureCooldown: TimeInterval
    public var calibrate: Bool
    public var configURL: URL?
    public var configOutURL: URL?

    public static func parse(arguments: [String]) -> Result<MacTouchProbeOptions, MacTouchProbeOptionsError> {
        let recordURL = parsePath(arguments, flag: "--record")
        let replayURL = parsePath(arguments, flag: "--replay")

        if recordURL != nil, replayURL != nil {
            return .failure(.recordAndReplayBothSpecified)
        }

        if let error = validateValuePresent(arguments, flag: "--duration") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--every") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--record") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--replay") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--notes") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--grouping") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--gesture-cooldown") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--config") { return .failure(error) }
        if let error = validateValuePresent(arguments, flag: "--config-out") { return .failure(error) }

        let recognizeGestures = arguments.contains("--gestures")
        let calibrate = arguments.contains("--calibrate")
        if calibrate, recordURL != nil || replayURL != nil {
            return .failure(.calibrateWithRecordOrReplay)
        }

        let explicitConfigOut = parsePath(arguments, flag: "--config-out")

        var configOutURL: URL?
        if calibrate {
            configOutURL = explicitConfigOut ?? MacTouchSettings.defaultConfigURL
        }

        let options = MacTouchProbeOptions(
            duration: parseDouble(arguments, flag: "--duration") ?? 8.0,
            printEvery: parseInt(arguments, flag: "--every") ?? 1,
            recordURL: recordURL,
            replayURL: replayURL,
            notes: parseString(arguments, flag: "--notes") ?? "",
            realtimeReplay: arguments.contains("--realtime"),
            showProcessed: arguments.contains("--process"),
            detectTaps: arguments.contains("--detect") || recognizeGestures,
            recognizeGestures: recognizeGestures,
            groupingWindow: parseDouble(arguments, flag: "--grouping") ?? 0.40,
            gestureCooldown: parseDouble(arguments, flag: "--gesture-cooldown") ?? 0.20,
            calibrate: calibrate,
            configURL: parsePath(arguments, flag: "--config"),
            configOutURL: configOutURL
        )

        return .success(options)
    }

    private static func validateValuePresent(_ args: [String], flag: String) -> MacTouchProbeOptionsError? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex, !args[valueIndex].hasPrefix("--") else {
            return .missingValue(forFlag: flag)
        }
        return nil
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

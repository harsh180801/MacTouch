import Foundation
import MacTouchCore

struct ShortcutRunResult: Equatable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol ShortcutCommandRunning: Sendable {
    func runShortcut(named name: String) throws -> ShortcutRunResult
}

protocol SystemMuteToggling: Sendable {
    /// Returns the new muted state after toggling.
    func toggleOutputMute() throws -> Bool
}

struct ProcessShortcutRunner: ShortcutCommandRunning {
    func runShortcut(named name: String) throws -> ShortcutRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return ShortcutRunResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }
}

struct ProcessMuteToggler: SystemMuteToggling {
    func toggleOutputMute() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "set mutedState to output muted of (get volume settings)",
            "-e", "if mutedState then",
            "-e", "set volume without output muted",
            "-e", "return \"off\"",
            "-e", "else",
            "-e", "set volume with output muted",
            "-e", "return \"on\"",
            "-e", "end if"
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "MacTouchMute",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "osascript exit \(process.terminationStatus)"]
            )
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return output.contains("true") || output.contains("on")
    }
}

enum ShortcutActionOutcome: Equatable, Sendable {
    enum SkipReason: String, Equatable, Sendable {
        case disabled
        case unmapped
        case cooldown
        case busy
    }

    case success(action: String)
    case failed(action: String, reason: String)
    case skipped(reason: SkipReason)

    var summary: String {
        switch self {
        case .success(let action):
            return "\(action) ✅"
        case .failed(let action, let reason):
            return "\(action) failed: \(reason)"
        case .skipped(let reason):
            return "Action skipped: \(reason.rawValue)"
        }
    }
}

final class ShortcutActionDispatcher: @unchecked Sendable {
    private let runner: ShortcutCommandRunning
    private let muteToggler: SystemMuteToggling
    private let lock = NSLock()
    private var running = false
    private var lastRunAt: TimeInterval?

    init(
        runner: ShortcutCommandRunning = ProcessShortcutRunner(),
        muteToggler: SystemMuteToggling = ProcessMuteToggler()
    ) {
        self.runner = runner
        self.muteToggler = muteToggler
    }

    func dispatch(
        gesture kind: TapGestureKind,
        settings: ActionSettings,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> ShortcutActionOutcome {
        guard settings.enabled else {
            return .skipped(reason: .disabled)
        }

        let actionKind = settings.actionKind(for: kind)
        let shortcutName = settings.shortcutName(for: kind)
        if actionKind == .none {
            return .skipped(reason: .unmapped)
        }
        if actionKind == .shortcut, shortcutName == nil {
            return .skipped(reason: .unmapped)
        }

        lock.lock()
        if running {
            lock.unlock()
            return .skipped(reason: .busy)
        }
        if let lastRunAt, now - lastRunAt < settings.cooldownSeconds {
            lock.unlock()
            return .skipped(reason: .cooldown)
        }
        running = true
        self.lastRunAt = now
        lock.unlock()

        defer {
            lock.lock()
            running = false
            lock.unlock()
        }

        do {
            switch actionKind {
            case .none:
                return .skipped(reason: .unmapped)
            case .shortcut:
                let name = shortcutName ?? "Shortcut"
                let result = try runner.runShortcut(named: name)
                guard result.exitCode == 0 else {
                    let output = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason = output.isEmpty ? "exit \(result.exitCode)" : output
                    return .failed(action: "Shortcut: \(name)", reason: reason)
                }
                return .success(action: "Shortcut: \(name)")
            case .toggleMute:
                let muted = try muteToggler.toggleOutputMute()
                return .success(action: "Output mute toggled \(muted ? "on" : "off")")
            }
        } catch {
            switch actionKind {
            case .none:
                return .skipped(reason: .unmapped)
            case .shortcut:
                let name = shortcutName ?? "Shortcut"
                return .failed(action: "Shortcut: \(name)", reason: error.localizedDescription)
            case .toggleMute:
                return .failed(action: "Output mute toggle", reason: error.localizedDescription)
            }
        }
    }
}

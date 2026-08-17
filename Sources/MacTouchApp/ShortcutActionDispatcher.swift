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

enum ShortcutActionOutcome: Equatable, Sendable {
    enum SkipReason: String, Equatable, Sendable {
        case disabled
        case unmapped
        case cooldown
        case busy
    }

    case success(name: String)
    case failed(name: String, reason: String)
    case skipped(reason: SkipReason)

    var summary: String {
        switch self {
        case .success(let name):
            return "Shortcut ran: \(name)"
        case .failed(let name, let reason):
            return "Shortcut failed (\(name)): \(reason)"
        case .skipped(let reason):
            return "Shortcut skipped: \(reason.rawValue)"
        }
    }
}

final class ShortcutActionDispatcher: @unchecked Sendable {
    private let runner: ShortcutCommandRunning
    private let lock = NSLock()
    private var running = false
    private var lastRunAt: TimeInterval?

    init(runner: ShortcutCommandRunning = ProcessShortcutRunner()) {
        self.runner = runner
    }

    func dispatch(
        gesture kind: TapGestureKind,
        settings: ActionSettings,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> ShortcutActionOutcome {
        guard settings.enabled else {
            return .skipped(reason: .disabled)
        }

        guard let name = settings.shortcutName(for: kind) else {
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
            let result = try runner.runShortcut(named: name)
            guard result.exitCode == 0 else {
                let output = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = output.isEmpty ? "exit \(result.exitCode)" : output
                return .failed(name: name, reason: reason)
            }
            return .success(name: name)
        } catch {
            return .failed(name: name, reason: error.localizedDescription)
        }
    }
}

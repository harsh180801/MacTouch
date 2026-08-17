import Foundation
import MacTouchCore
import Testing
@testable import MacTouchApp

private struct StubRunner: ShortcutCommandRunning {
    var handler: @Sendable (String) throws -> ShortcutRunResult

    func runShortcut(named name: String) throws -> ShortcutRunResult {
        try handler(name)
    }
}

private struct StubMuteToggler: SystemMuteToggling {
    var handler: @Sendable () throws -> Bool

    func toggleOutputMute() throws -> Bool {
        try handler()
    }
}

private struct StubAppOpener: AppOpening {
    var handler: @Sendable (String) throws -> Void

    func openApp(named appName: String) throws {
        try handler(appName)
    }
}

private struct StubNotifier: UserNotifying {
    var handler: @Sendable (String, String) throws -> Void

    func notify(title: String, body: String) throws {
        try handler(title, body)
    }
}

private final class NotificationCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (String, String)?

    func set(_ newValue: (String, String)) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> (String, String)? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct ShortcutActionDispatcherTests {
    @Test func skipsWhenDisabled() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: false,
            doubleShortcutName: "Focus Timer",
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        #expect(outcome == .skipped(reason: .disabled))
    }

    @Test func skipsWhenUnmapped() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(enabled: true, cooldownSeconds: 1.0)
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        #expect(outcome == .skipped(reason: .unmapped))
    }

    @Test func enforcesCooldown() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Focus Timer",
            doubleActionKind: .shortcut,
            cooldownSeconds: 1.5
        )
        let first = dispatcher.dispatch(gesture: .double, settings: settings, now: 10.0)
        let second = dispatcher.dispatch(gesture: .double, settings: settings, now: 10.8)
        #expect(first == .success(action: "Shortcut: Focus Timer"))
        #expect(second == .skipped(reason: .cooldown))
    }

    @Test func reportsFailureWithStderr() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 1, stdout: "", stderr: "No Shortcut found")
            },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Missing",
            doubleActionKind: .shortcut,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        #expect(outcome == .failed(action: "Shortcut: Missing", reason: "No Shortcut found"))
    }

    @Test func reportsLaunchFailure() {
        enum TestError: Error { case boom }

        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                throw TestError.boom
            },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Any",
            doubleActionKind: .shortcut,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        if case .failed(action: "Shortcut: Any", reason: let reason) = outcome {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected failed outcome, got \(outcome)")
        }
    }

    @Test func togglesMuteWhenConfigured() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            },
            muteToggler: StubMuteToggler { true },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: true,
            singleActionKind: .toggleMute,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .single, settings: settings, now: 10)
        #expect(outcome == .success(action: "Output mute toggled on"))
    }

    @Test func launchesAppWhenConfigured() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in ShortcutRunResult(exitCode: 0, stdout: "", stderr: "") },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { _, _ in }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleAppName: "Safari",
            doubleActionKind: .launchApp,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 11)
        #expect(outcome == .success(action: "App launched: Safari"))
    }

    @Test func showsNotificationWhenConfigured() {
        let captured = NotificationCaptureBox()
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in ShortcutRunResult(exitCode: 0, stdout: "", stderr: "") },
            muteToggler: StubMuteToggler { false },
            appOpener: StubAppOpener { _ in },
            notifier: StubNotifier { title, body in
                captured.set((title, body))
            }
        )
        let settings = ActionSettings(
            enabled: true,
            notificationTitle: "MacTouch",
            notificationBody: "Triggered",
            tripleActionKind: .notify,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .triple, settings: settings, now: 12)
        #expect(outcome == .success(action: "Notification shown"))
        #expect(captured.get()?.0 == "MacTouch")
        #expect(captured.get()?.1 == "Triggered")
    }
}

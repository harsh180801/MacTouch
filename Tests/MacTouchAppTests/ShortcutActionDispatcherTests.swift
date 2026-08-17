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

struct ShortcutActionDispatcherTests {
    @Test func skipsWhenDisabled() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            }
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
            }
        )
        let settings = ActionSettings(enabled: true, cooldownSeconds: 1.0)
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        #expect(outcome == .skipped(reason: .unmapped))
    }

    @Test func enforcesCooldown() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Focus Timer",
            cooldownSeconds: 1.5
        )
        let first = dispatcher.dispatch(gesture: .double, settings: settings, now: 10.0)
        let second = dispatcher.dispatch(gesture: .double, settings: settings, now: 10.8)
        #expect(first == .success(name: "Focus Timer"))
        #expect(second == .skipped(reason: .cooldown))
    }

    @Test func reportsFailureWithStderr() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 1, stdout: "", stderr: "No Shortcut found")
            }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Missing",
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        #expect(outcome == .failed(name: "Missing", reason: "No Shortcut found"))
    }

    @Test func reportsLaunchFailure() {
        enum TestError: Error { case boom }

        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                throw TestError.boom
            }
        )
        let settings = ActionSettings(
            enabled: true,
            doubleShortcutName: "Any",
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .double, settings: settings, now: 10)
        if case .failed(name: "Any", reason: let reason) = outcome {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected failed outcome, got \(outcome)")
        }
    }
}

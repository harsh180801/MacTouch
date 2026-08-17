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

struct ShortcutActionDispatcherTests {
    @Test func skipsWhenDisabled() {
        let dispatcher = ShortcutActionDispatcher(
            runner: StubRunner { _ in
                ShortcutRunResult(exitCode: 0, stdout: "", stderr: "")
            },
            muteToggler: StubMuteToggler { false }
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
            muteToggler: StubMuteToggler { false }
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
            muteToggler: StubMuteToggler { false }
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
            muteToggler: StubMuteToggler { false }
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
            muteToggler: StubMuteToggler { false }
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
            muteToggler: StubMuteToggler { true }
        )
        let settings = ActionSettings(
            enabled: true,
            singleActionKind: .toggleMute,
            cooldownSeconds: 1.0
        )
        let outcome = dispatcher.dispatch(gesture: .single, settings: settings, now: 10)
        #expect(outcome == .success(action: "Output mute toggled on"))
    }
}

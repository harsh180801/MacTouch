import Foundation
import Testing
@testable import MacTouchCore

struct MacTouchProbeOptionsTests {
    @Test func parsesCalibrateAndConfigOut() throws {
        let options = try MacTouchProbeOptions.parse(arguments: [
            "--calibrate", "--config-out", "/tmp/mactouch-settings.json"
        ]).get()
        #expect(options.calibrate == true)
        #expect(options.configOutURL?.path == "/tmp/mactouch-settings.json")
    }

    @Test func calibrateDefaultsConfigOutToHomeConfig() throws {
        let options = try MacTouchProbeOptions.parse(arguments: ["--calibrate"]).get()
        #expect(options.calibrate == true)
        #expect(options.configOutURL == MacTouchSettings.defaultConfigURL)
    }

    @Test func parsesConfigForGestures() throws {
        let options = try MacTouchProbeOptions.parse(arguments: [
            "--gestures", "--config", "/tmp/in.json"
        ]).get()
        #expect(options.recognizeGestures == true)
        #expect(options.configURL?.path == "/tmp/in.json")
    }
}

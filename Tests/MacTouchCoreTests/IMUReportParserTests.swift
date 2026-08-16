import Foundation
import Testing
@testable import MacTouchCore

struct IMUReportParserTests {
    @Test func rejectsWrongLength() {
        #expect(IMUReportParser.parseXYZ(bytes: [UInt8](repeating: 0, count: 21)) == nil)
        #expect(IMUReportParser.parseXYZ(bytes: [UInt8](repeating: 0, count: 23)) == nil)
    }

    @Test func decodesQ16LittleEndianXYZ() {
        // Build a 22-byte report with X=1g, Y=-0.5g, Z=0 at Q16 scale.
        var bytes = [UInt8](repeating: 0, count: IMUReportParser.reportLength)
        writeInt32LE(&bytes, offset: 6, value: 65536)       // +1.0 g
        writeInt32LE(&bytes, offset: 10, value: -32768)     // -0.5 g
        writeInt32LE(&bytes, offset: 14, value: 0)          //  0.0 g

        let parsed = IMUReportParser.parseXYZ(bytes: bytes)
        #expect(parsed != nil)
        #expect(abs(parsed!.x - 1.0) < 1e-9)
        #expect(abs(parsed!.y - (-0.5)) < 1e-9)
        #expect(abs(parsed!.z - 0.0) < 1e-9)
    }

    @Test func sensorSampleMagnitude() {
        let sample = SensorSample(timestamp: 1, x: 3, y: 4, z: 0)
        #expect(abs(sample.magnitude - 5.0) < 1e-9)
    }
}

private func writeInt32LE(_ bytes: inout [UInt8], offset: Int, value: Int32) {
    let pattern = UInt32(bitPattern: value)
    bytes[offset] = UInt8(pattern & 0xFF)
    bytes[offset + 1] = UInt8((pattern >> 8) & 0xFF)
    bytes[offset + 2] = UInt8((pattern >> 16) & 0xFF)
    bytes[offset + 3] = UInt8((pattern >> 24) & 0xFF)
}

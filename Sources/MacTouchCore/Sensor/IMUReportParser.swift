import Foundation

/// Parses undocumented Apple SPU / BMI286-style HID input reports.
///
/// Community-documented layout (olvvier/apple-silicon-accelerometer and ports):
/// - Report length: 22 bytes for accelerometer (and gyroscope) IMU reports
/// - Bytes 0..<6: header / metadata (not used for XYZ)
/// - Bytes 6..<10 / 10..<14 / 14..<18: little-endian int32 X / Y / Z
/// - Scale: Q16 fixed-point → divide by 65536 to get g (accel) or deg/s (gyro)
///
/// These constants are hardware-specific and not part of a public Apple API.
public enum IMUReportParser {
    /// Vendor HID usage page used by AppleSPUHIDDevice IMU endpoints.
    public static let vendorUsagePage = 0xFF00

    /// PrimaryUsage for the accelerometer endpoint on AppleSPUHIDDevice.
    public static let accelerometerUsage = 3

    /// PrimaryUsage for the gyroscope endpoint (same physical IMU).
    public static let gyroscopeUsage = 9

    /// Expected accelerometer / gyroscope input report length in bytes.
    public static let reportLength = 22

    /// Byte offset where little-endian int32 XYZ begins.
    public static let payloadOffset = 6

    /// Q16 scale factor: raw_int32 / scale → physical units.
    public static let q16Scale = 65536.0

    /// Decode one IMU report into acceleration (or angular rate) in physical units.
    ///
    /// Returns `nil` when the buffer is too short or clearly not a 22-byte IMU frame.
    public static func parseXYZ(report: UnsafePointer<UInt8>, length: Int) -> (x: Double, y: Double, z: Double)? {
        guard length == reportLength else { return nil }

        let xRaw = int32LittleEndian(report, offset: payloadOffset)
        let yRaw = int32LittleEndian(report, offset: payloadOffset + 4)
        let zRaw = int32LittleEndian(report, offset: payloadOffset + 8)

        return (
            x: Double(xRaw) / q16Scale,
            y: Double(yRaw) / q16Scale,
            z: Double(zRaw) / q16Scale
        )
    }

    /// Convenience for tests and offline tooling that already hold a `[UInt8]` buffer.
    public static func parseXYZ(bytes: [UInt8]) -> (x: Double, y: Double, z: Double)? {
        guard bytes.count == reportLength else { return nil }
        return bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return nil }
            return parseXYZ(report: base, length: buffer.count)
        }
    }

    private static func int32LittleEndian(_ report: UnsafePointer<UInt8>, offset: Int) -> Int32 {
        let b0 = UInt32(report[offset])
        let b1 = UInt32(report[offset + 1]) << 8
        let b2 = UInt32(report[offset + 2]) << 16
        let b3 = UInt32(report[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }
}

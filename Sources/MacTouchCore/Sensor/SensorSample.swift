import Foundation

/// One timestamped 3-axis accelerometer reading from the Apple SPU HID device.
///
/// Values are acceleration in **g** (Earth gravity ≈ 1.0 at rest along the
/// vertical axis). This is chassis vibration data, not touchscreen input.
public struct SensorSample: Equatable, Sendable, Codable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let z: Double

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case x, y, z
    }

    public init(timestamp: TimeInterval, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }

    /// Euclidean magnitude of the acceleration vector in g.
    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

import Foundation
import IOKit
import IOKit.hid

/// Errors from discovering or opening the Apple SPU accelerometer.
public enum SensorServiceError: Error, LocalizedError, Equatable {
    case deviceUnavailable
    case openFailed(kern_return_t)
    case alreadyRunning
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "No AppleSPUHID accelerometer was found (PrimaryUsagePage=0xFF00, PrimaryUsage=3)."
        case .openFailed(let status):
            return "IOHIDDeviceOpen failed with status \(status) (0x\(String(status, radix: 16))). Try Input Monitoring permission; elevate only if that fails."
        case .alreadyRunning:
            return "SensorService is already running."
        case .notRunning:
            return "SensorService is not running."
        }
    }
}

/// Discovers and streams the Apple Silicon MacBook chassis accelerometer via IOKit HID.
///
/// Privilege policy (Phase 1): open as the current user first. Do not require root
/// unless wake/stream fails and a later phase explicitly documents why elevation is needed.
///
/// Approach studied from community projects (MIT-licensed ideas, reimplemented here):
/// olvvier/apple-silicon-accelerometer, shaircast/nocnoc, AbdullahFID/MacSlapApp.
public final class SensorService: @unchecked Sendable {
    public var onSample: (@Sendable (SensorSample) -> Void)?

    private let queue = DispatchQueue(label: "com.mactouch.sensor", qos: .userInteractive)
    private var deviceHandles: [DeviceHandle] = []
    private var isRunning = false
    private let stateLock = NSLock()

    public init() {}

    /// True when an accelerometer-matching AppleSPUHIDDevice exists (no open required).
    public func isAvailable() -> Bool {
        let services = matchingAccelerometerServices()
        defer {
            for service in services {
                IOObjectRelease(service)
            }
        }
        return !services.isEmpty
    }

    /// Wake drivers, open matching HID devices, and begin delivering samples.
    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else { throw SensorServiceError.alreadyRunning }

        wakeSPUDrivers()

        let services = matchingAccelerometerServices()
        guard !services.isEmpty else {
            throw SensorServiceError.deviceUnavailable
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var opened: [DeviceHandle] = []

        for service in services {
            defer { IOObjectRelease(service) }

            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                continue
            }

            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                for handle in opened {
                    handle.stop()
                }
                throw SensorServiceError.openFailed(status)
            }

            // Wake again after open: some machines only start streaming once the
            // HID client is attached (documented by MacSlapApp / community ports).
            wakeSPUDrivers()

            let handle = DeviceHandle(device: device)
            handle.activate(queue: queue, callback: Self.reportCallback, context: context)
            opened.append(handle)
        }

        guard !opened.isEmpty else {
            throw SensorServiceError.deviceUnavailable
        }

        deviceHandles = opened
        isRunning = true
    }

    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRunning else { return }
        for handle in deviceHandles {
            handle.stop()
        }
        deviceHandles.removeAll()
        isRunning = false
    }

    public var running: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    // MARK: - HID callback

    private static let reportCallback: IOHIDReportWithTimeStampCallback = { context, _, _, _, _, report, reportLength, _ in
        guard let context else { return }
        let service = Unmanaged<SensorService>.fromOpaque(context).takeUnretainedValue()
        service.handleReport(report, length: Int(reportLength))
    }

    private func handleReport(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard let xyz = IMUReportParser.parseXYZ(report: report, length: length) else { return }
        let sample = SensorSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            x: xyz.x,
            y: xyz.y,
            z: xyz.z
        )
        onSample?(sample)
    }

    // MARK: - IOKit discovery / wake

    /// Power on reporting for AppleSPUHIDDriver instances.
    ///
    /// These property names come from community reverse-engineering of the SPU stack.
    /// Setting them on the IOHIDDevice alone is often ignored; the driver service owns state.
    private func wakeSPUDrivers() {
        guard let matching = IOServiceMatching("AppleSPUHIDDriver") else { return }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            setDriverInt32(service, key: "SensorPropertyReportingState", value: 1)
            setDriverInt32(service, key: "SensorPropertyPowerState", value: 1)
            // 1000 µs requested interval ≈ 1 kHz; hardware often delivers ~800 Hz.
            setDriverInt32(service, key: "ReportInterval", value: 1000)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func setDriverInt32(_ service: io_service_t, key: String, value: Int32) {
        var mutableValue = value
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &mutableValue) else {
            return
        }
        IORegistryEntrySetCFProperty(service, key as CFString, number)
    }

    private func matchingAccelerometerServices() -> [io_service_t] {
        guard let matching = IOServiceMatching("AppleSPUHIDDevice") else {
            return []
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var matches: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let usagePage = propertyInt(service, key: "PrimaryUsagePage")
            let usage = propertyInt(service, key: "PrimaryUsage")

            if usagePage == IMUReportParser.vendorUsagePage,
               usage == IMUReportParser.accelerometerUsage {
                matches.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        return matches
    }

    private func propertyInt(_ service: io_service_t, key: String) -> Int? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return (property as? NSNumber)?.intValue
    }
}

// MARK: - Device handle

private final class DeviceHandle {
    static let reportBufferSize = 4096

    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>

    init(device: IOHIDDevice) {
        self.device = device
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportBufferSize)
        self.buffer.initialize(repeating: 0, count: Self.reportBufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    func activate(
        queue: DispatchQueue,
        callback: IOHIDReportWithTimeStampCallback,
        context: UnsafeMutableRawPointer
    ) {
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device,
            buffer,
            Self.reportBufferSize,
            callback,
            context
        )
        IOHIDDeviceActivate(device)
    }

    func stop() {
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

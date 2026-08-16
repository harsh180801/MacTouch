import Foundation

/// Tunable signal-processing parameters. Every non-obvious default is documented.
public struct SignalProcessorConfig: Equatable, Sendable {
    /// Assumed delivery rate used when converting time constants → filter coefficients.
    /// Measured ~800–805 Hz on Apple Silicon MacBook SPU IMU streams in Phase 1.
    public var sampleRateHz: Double

    /// Gravity low-pass time constant in seconds.
    /// ~0.5 s keeps orientation drift while stripping steady 1g bias (similar intent to
    /// MacSlapApp’s EMA with alpha≈0.9975 at ~805 Hz).
    public var gravityTimeConstantSeconds: Double

    /// High-pass cutoff used after gravity removal to emphasize short chassis impacts.
    /// ~8–12 Hz isolates taps better than typing rock; 10 Hz is a starting point
    /// (community tap pipelines often high-pass around this band).
    public var impactHighPassCutoffHz: Double

    /// Optional low-pass after the high-pass (band-pass upper edge). `nil` disables.
    /// When set (e.g. 80 Hz), attenuates very high-frequency sensor noise.
    public var impactLowPassCutoffHz: Double?

    /// Noise-floor EMA time constant (seconds) while the signal is quiet.
    public var noiseFloorTimeConstantSeconds: Double

    /// Treat the signal as “elevated” (freeze noise learning) when
    /// `filteredMagnitude > noiseFloor + elevatedSigma * noiseDeviation + elevatedMargin`.
    public var elevatedSigma: Double

    /// Absolute margin (g) added to the elevated test so tiny floors still freeze on taps.
    public var elevatedMarginG: Double

    public init(
        sampleRateHz: Double = 800,
        gravityTimeConstantSeconds: Double = 0.5,
        impactHighPassCutoffHz: Double = 10,
        impactLowPassCutoffHz: Double? = 80,
        noiseFloorTimeConstantSeconds: Double = 1.0,
        elevatedSigma: Double = 4,
        elevatedMarginG: Double = 0.02
    ) {
        self.sampleRateHz = sampleRateHz
        self.gravityTimeConstantSeconds = gravityTimeConstantSeconds
        self.impactHighPassCutoffHz = impactHighPassCutoffHz
        self.impactLowPassCutoffHz = impactLowPassCutoffHz
        self.noiseFloorTimeConstantSeconds = noiseFloorTimeConstantSeconds
        self.elevatedSigma = elevatedSigma
        self.elevatedMarginG = elevatedMarginG
    }
}

/// One processed frame derived from a raw `SensorSample`.
public struct ProcessedSample: Equatable, Sendable {
    public let timestamp: TimeInterval

    /// Raw acceleration axes (g).
    public let x: Double
    public let y: Double
    public let z: Double

    /// Raw vector magnitude √(x²+y²+z²) (≈1 at rest due to gravity).
    public let rawMagnitude: Double

    /// Acceleration with estimated gravity removed (dynamic accel per axis, g).
    public let linearX: Double
    public let linearY: Double
    public let linearZ: Double

    /// Magnitude of the linear (gravity-removed) vector.
    public let linearMagnitude: Double

    /// Impact-oriented filtered magnitude (high-pass / band-pass of linear signal).
    public let filteredMagnitude: Double

    /// Rolling quiet-baseline estimate of filtered magnitude.
    public let noiseFloor: Double

    /// Rolling absolute-deviation estimate around the noise floor.
    public let noiseDeviation: Double

    /// `filteredMagnitude` relative to the adaptive floor:
    /// max(0, (filtered - floor) / max(deviation, epsilon)).
    public let normalizedExcess: Double

    public init(
        timestamp: TimeInterval,
        x: Double,
        y: Double,
        z: Double,
        rawMagnitude: Double,
        linearX: Double,
        linearY: Double,
        linearZ: Double,
        linearMagnitude: Double,
        filteredMagnitude: Double,
        noiseFloor: Double,
        noiseDeviation: Double,
        normalizedExcess: Double
    ) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
        self.rawMagnitude = rawMagnitude
        self.linearX = linearX
        self.linearY = linearY
        self.linearZ = linearZ
        self.linearMagnitude = linearMagnitude
        self.filteredMagnitude = filteredMagnitude
        self.noiseFloor = noiseFloor
        self.noiseDeviation = noiseDeviation
        self.normalizedExcess = normalizedExcess
    }
}

/// Streaming signal processor: gravity removal → impact band filter → noise baseline.
public final class SignalProcessor: @unchecked Sendable {
    public private(set) var config: SignalProcessorConfig

    private var gravityX = 0.0
    private var gravityY = 0.0
    private var gravityZ = 0.0
    private var gravityReady = false

    private var highPass: FirstOrderHighPass3
    private var lowPass: FirstOrderLowPass?
    private var noiseFloor = 0.0
    private var noiseDeviation = 0.01
    private var noiseReady = false
    private var sampleIndex = 0

    public init(config: SignalProcessorConfig = SignalProcessorConfig()) {
        self.config = config
        self.highPass = FirstOrderHighPass3(
            cutoffHz: config.impactHighPassCutoffHz,
            sampleRateHz: config.sampleRateHz
        )
        if let lowCutoff = config.impactLowPassCutoffHz {
            self.lowPass = FirstOrderLowPass(cutoffHz: lowCutoff, sampleRateHz: config.sampleRateHz)
        } else {
            self.lowPass = nil
        }
    }

    public func reset() {
        gravityX = 0
        gravityY = 0
        gravityZ = 0
        gravityReady = false
        highPass.reset()
        lowPass?.reset()
        noiseFloor = 0
        noiseDeviation = 0.01
        noiseReady = false
        sampleIndex = 0
    }

    public func updateConfig(_ config: SignalProcessorConfig) {
        self.config = config
        highPass = FirstOrderHighPass3(
            cutoffHz: config.impactHighPassCutoffHz,
            sampleRateHz: config.sampleRateHz
        )
        if let lowCutoff = config.impactLowPassCutoffHz {
            lowPass = FirstOrderLowPass(cutoffHz: lowCutoff, sampleRateHz: config.sampleRateHz)
        } else {
            lowPass = nil
        }
        reset()
    }

    public func process(_ sample: SensorSample) -> ProcessedSample {
        sampleIndex += 1
        let rawMagnitude = SignalMath.magnitude(sample.x, sample.y, sample.z)

        // 1) Estimate gravity with a slow EMA (equivalent to a 1st-order low-pass).
        let gravityAlpha = SignalMath.emaAlpha(
            timeConstantSeconds: config.gravityTimeConstantSeconds,
            sampleRateHz: config.sampleRateHz
        )
        if !gravityReady {
            gravityX = sample.x
            gravityY = sample.y
            gravityZ = sample.z
            gravityReady = true
        } else {
            gravityX = gravityAlpha * gravityX + (1 - gravityAlpha) * sample.x
            gravityY = gravityAlpha * gravityY + (1 - gravityAlpha) * sample.y
            gravityZ = gravityAlpha * gravityZ + (1 - gravityAlpha) * sample.z
        }

        let linearX = sample.x - gravityX
        let linearY = sample.y - gravityY
        let linearZ = sample.z - gravityZ
        let linearMagnitude = SignalMath.magnitude(linearX, linearY, linearZ)

        // 2) High-pass (and optional low-pass) the linear vector, then take magnitude.
        let hp = highPass.process(x: linearX, y: linearY, z: linearZ)
        var filteredMagnitude = SignalMath.magnitude(hp.x, hp.y, hp.z)
        if var lowPass {
            filteredMagnitude = lowPass.process(filteredMagnitude)
            self.lowPass = lowPass
        }

        // 3) Rolling noise baseline — freeze while elevated so taps do not inflate the floor.
        let elevatedThreshold = noiseFloor + config.elevatedSigma * noiseDeviation + config.elevatedMarginG
        let elevated = noiseReady && filteredMagnitude > elevatedThreshold
        let noiseAlpha = SignalMath.emaAlpha(
            timeConstantSeconds: config.noiseFloorTimeConstantSeconds,
            sampleRateHz: config.sampleRateHz
        )
        if !noiseReady {
            noiseFloor = filteredMagnitude
            noiseDeviation = 0.01
            noiseReady = true
        } else if !elevated {
            noiseFloor = noiseAlpha * noiseFloor + (1 - noiseAlpha) * filteredMagnitude
            noiseDeviation = noiseAlpha * noiseDeviation + (1 - noiseAlpha) * abs(filteredMagnitude - noiseFloor)
        }

        let denom = max(noiseDeviation, 1e-6)
        let normalizedExcess = max(0, (filteredMagnitude - noiseFloor) / denom)

        return ProcessedSample(
            timestamp: sample.timestamp,
            x: sample.x,
            y: sample.y,
            z: sample.z,
            rawMagnitude: rawMagnitude,
            linearX: linearX,
            linearY: linearY,
            linearZ: linearZ,
            linearMagnitude: linearMagnitude,
            filteredMagnitude: filteredMagnitude,
            noiseFloor: noiseFloor,
            noiseDeviation: noiseDeviation,
            normalizedExcess: normalizedExcess
        )
    }
}

// MARK: - Shared math

public enum SignalMath {
    public static func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// EMA coefficient for a given time constant τ at sample rate fs:
    /// α = exp(-1 / (τ * fs)). Large α ⇒ slower tracking.
    public static func emaAlpha(timeConstantSeconds: Double, sampleRateHz: Double) -> Double {
        let safeTau = max(timeConstantSeconds, 1e-6)
        let safeFs = max(sampleRateHz, 1)
        return exp(-1.0 / (safeTau * safeFs))
    }

    /// First-order low-pass coefficient for cutoff fc at sample rate fs (RC discretization).
    /// α = dt / (RC + dt) with RC = 1 / (2π fc).
    public static func lowPassAlpha(cutoffHz: Double, sampleRateHz: Double) -> Double {
        let safeFc = max(cutoffHz, 1e-6)
        let dt = 1.0 / max(sampleRateHz, 1)
        let rc = 1.0 / (2.0 * Double.pi * safeFc)
        return dt / (rc + dt)
    }
}

// MARK: - Filters

/// Scalar first-order low-pass: y[n] = y[n-1] + α (x[n] - y[n-1]).
public struct FirstOrderLowPass: Equatable, Sendable {
    public let alpha: Double
    private var previous: Double?
    private var initialized = false

    public init(cutoffHz: Double, sampleRateHz: Double) {
        self.alpha = SignalMath.lowPassAlpha(cutoffHz: cutoffHz, sampleRateHz: sampleRateHz)
    }

    public init(alpha: Double) {
        self.alpha = min(max(alpha, 0), 1)
    }

    public mutating func reset() {
        previous = nil
        initialized = false
    }

    public mutating func process(_ input: Double) -> Double {
        guard initialized, let previous else {
            self.previous = input
            initialized = true
            return input
        }
        let output = previous + alpha * (input - previous)
        self.previous = output
        return output
    }
}

/// Per-axis first-order high-pass (DC blocker style):
/// y[n] = α * (y[n-1] + x[n] - x[n-1]), with α derived from cutoff.
///
/// Same family as classic one-pole HP used in IMU demos / seismology-lite pipelines.
public struct FirstOrderHighPass3: Equatable, Sendable {
    public let alpha: Double
    private var prevInX = 0.0, prevInY = 0.0, prevInZ = 0.0
    private var prevOutX = 0.0, prevOutY = 0.0, prevOutZ = 0.0
    private var ready = false

    public init(cutoffHz: Double, sampleRateHz: Double) {
        // α = RC / (RC + dt), RC = 1/(2π fc)
        let safeFc = max(cutoffHz, 1e-6)
        let dt = 1.0 / max(sampleRateHz, 1)
        let rc = 1.0 / (2.0 * Double.pi * safeFc)
        self.alpha = rc / (rc + dt)
    }

    public init(alpha: Double) {
        self.alpha = min(max(alpha, 0), 1)
    }

    public mutating func reset() {
        prevInX = 0
        prevInY = 0
        prevInZ = 0
        prevOutX = 0
        prevOutY = 0
        prevOutZ = 0
        ready = false
    }

    public mutating func process(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        if !ready {
            prevInX = x
            prevInY = y
            prevInZ = z
            ready = true
            return (0, 0, 0)
        }
        let outX = alpha * (prevOutX + x - prevInX)
        let outY = alpha * (prevOutY + y - prevInY)
        let outZ = alpha * (prevOutZ + z - prevInZ)
        prevInX = x
        prevInY = y
        prevInZ = z
        prevOutX = outX
        prevOutY = outY
        prevOutZ = outZ
        return (outX, outY, outZ)
    }
}

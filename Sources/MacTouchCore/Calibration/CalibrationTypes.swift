import Foundation

public enum CalibrationStage: String, Equatable, Sendable {
    case idle
    case singles
    case doubles
    case done
}

public struct CalibrationProgress: Equatable, Sendable {
    public var stage: CalibrationStage
    public var prompt: String
    public var idleSamples: Int
    public var singleCount: Int
    public var doublePairCount: Int
    public var requiredSingles: Int
    public var requiredDoubles: Int

    public init(
        stage: CalibrationStage,
        prompt: String,
        idleSamples: Int,
        singleCount: Int,
        doublePairCount: Int,
        requiredSingles: Int,
        requiredDoubles: Int
    ) {
        self.stage = stage
        self.prompt = prompt
        self.idleSamples = idleSamples
        self.singleCount = singleCount
        self.doublePairCount = doublePairCount
        self.requiredSingles = requiredSingles
        self.requiredDoubles = requiredDoubles
    }
}

public struct CalibrationSessionConfig: Equatable, Sendable {
    public var idleDurationSeconds: TimeInterval
    public var idleWarmupSeconds: TimeInterval
    public var requiredSingles: Int
    public var requiredDoubles: Int
    public var singleMinGapSeconds: TimeInterval
    public var doubleMinGapSeconds: TimeInterval
    public var doubleMaxGapSeconds: TimeInterval

    public init(
        idleDurationSeconds: TimeInterval = 4.0,
        idleWarmupSeconds: TimeInterval = 0.5,
        requiredSingles: Int = 5,
        requiredDoubles: Int = 5,
        singleMinGapSeconds: TimeInterval = 0.5,
        doubleMinGapSeconds: TimeInterval = 0.05,
        doubleMaxGapSeconds: TimeInterval = 0.35
    ) {
        self.idleDurationSeconds = idleDurationSeconds
        self.idleWarmupSeconds = idleWarmupSeconds
        self.requiredSingles = requiredSingles
        self.requiredDoubles = requiredDoubles
        self.singleMinGapSeconds = singleMinGapSeconds
        self.doubleMinGapSeconds = doubleMinGapSeconds
        self.doubleMaxGapSeconds = doubleMaxGapSeconds
    }
}

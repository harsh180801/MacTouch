import Foundation

struct WaveformBuffer: Sendable {
    private(set) var capacity: Int
    private var samples: [Double] = []

    init(capacity: Int = 96) {
        self.capacity = max(16, capacity)
    }

    mutating func append(_ value: Double) {
        samples.append(max(0, value))
        let overflow = samples.count - capacity
        if overflow > 0 {
            samples.removeFirst(overflow)
        }
    }

    func normalized(reference: Double, minFloor: Double = 0.002) -> [Double] {
        guard !samples.isEmpty else { return [] }
        let maxValue = max(reference, minFloor)
        return samples.map { min(1.0, $0 / maxValue) }
    }
}

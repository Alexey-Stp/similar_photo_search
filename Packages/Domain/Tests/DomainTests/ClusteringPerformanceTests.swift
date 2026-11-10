import Domain
import Foundation
import Testing

private let isDevicePerformanceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Device-only: run on an iPhone 13 with the scheme environment variable `RUN_DEVICE_PERFORMANCE_TESTS=1`.
/// Synthetic Revision 2-sized (768) unit vectors; groups of near-copies give edges and clusters, the rest are random.
struct ClusteringPerformanceTests {
    private let engine = UnionFindClusteringEngine()
    /// Not a calibrated value: random unit vectors are about 1.41 apart, near-copies about 0.1.
    private let config = ClusteringConfig(thresholds: [2: 0.5])

    /// A 500-photo session clusters in under 200 ms.
    @Test(.enabled(if: isDevicePerformanceRun, "Device-only performance test"))
    func fiveHundredPhotoSessionUnderTwoHundredMilliseconds() throws {
        var generator = SplitMix64(seed: 16)
        let session = Self.session(count: 500, start: Date(timeIntervalSince1970: 1_700_000_000), using: &generator)

        let clock = ContinuousClock()
        var result: [SimilarityCluster] = []
        let elapsed = try clock.measure { result = try engine.clusters(in: session, config: config) }

        #expect(!result.isEmpty)
        #expect(elapsed < .milliseconds(200), "500-photo session took \(elapsed)")
    }

    /// A 20,000-photo library, split into sessions of 1 to 60 photos, clusters in under 3 s in total.
    @Test(.enabled(if: isDevicePerformanceRun, "Device-only performance test"))
    func twentyThousandPhotoLibraryUnderThreeSeconds() throws {
        var generator = SplitMix64(seed: 26)
        var sessions: [[VectorItem]] = []
        var total = 0
        var start = Date(timeIntervalSince1970: 1_600_000_000)
        while total < 20_000 {
            let count = min(Int(generator.next() % 60) + 1, 20_000 - total)
            sessions.append(Self.session(count: count, start: start, using: &generator))
            total += count
            start = start.addingTimeInterval(86_400)
        }

        let clock = ContinuousClock()
        var clusterCount = 0
        let elapsed = try clock.measure {
            for session in sessions {
                clusterCount += try engine.clusters(in: session, config: config).count
            }
        }

        #expect(clusterCount > 0)
        #expect(elapsed < .seconds(3), "20,000-photo library took \(elapsed)")
    }

    /// `count` photos 5 s apart; every block of 5 is near-copies of one random vector.
    private static func session(count: Int, start: Date, using generator: inout SplitMix64) -> [VectorItem] {
        var items: [VectorItem] = []
        var base = randomUnitVector(using: &generator)
        for index in 0..<count {
            if index % 5 == 0 { base = randomUnitVector(using: &generator) }
            let vector = base.map { $0 + (Float(generator.nextUnit()) - 0.5) * 0.008 }
            items.append(VectorItem(
                id: "photo-\(start.timeIntervalSince1970)-\(index)",
                date: start.addingTimeInterval(TimeInterval(index) * 5),
                revision: 2,
                vector: vector
            ))
        }
        return items
    }

    private static func randomUnitVector(using generator: inout SplitMix64) -> [Float] {
        let raw = (0..<768).map { _ in Float(generator.nextUnit()) - 0.5 }
        let length = raw.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return raw.map { $0 / length }
    }
}

/// Small seeded generator so performance inputs are the same on every run.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A value in `0..<1`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

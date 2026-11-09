import DataLayer
import Foundation

/// Thread-safe `FeaturePrintExtracting` fake. Records calls, the most calls running at once and whether any call ran
/// on the main thread; can fail chosen calls and take a fixed time per call.
final class MockFeaturePrintExtractor: FeaturePrintExtracting, @unchecked Sendable {
    /// The error thrown by a failing call, like Vision's for an image that is too small.
    struct VisionError: Error {}

    let revision: Int
    private let vector: [Float]
    private let duration: TimeInterval
    private let failingCalls: Set<Int>
    private let lock = NSLock()
    private var calls = 0
    private var inFlight = 0
    private var maxInFlight = 0
    private var mainThreadCalls = 0

    /// - Parameters:
    ///   - failingCalls: Zero-based indexes of the calls that throw `VisionError`.
    ///   - duration: How long each call blocks its thread.
    init(
        revision: Int = 2,
        vector: [Float] = [0.1, 0.2, 0.3],
        duration: TimeInterval = 0,
        failingCalls: Set<Int> = []
    ) {
        self.revision = revision
        self.vector = vector
        self.duration = duration
        self.failingCalls = failingCalls
    }

    /// Calls so far.
    var callCount: Int { locked { calls } }
    /// The most calls that ran at the same time.
    var maxCallsAtOnce: Int { locked { maxInFlight } }
    /// Calls that ran on the main thread.
    var callsOnMainThread: Int { locked { mainThreadCalls } }

    /// Records the call, blocks for `duration`, then returns the preset vector or throws `VisionError`.
    func extract(from image: LoadedImage) throws -> ExtractedFeaturePrint {
        let index = locked {
            defer { calls += 1 }
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            if Thread.isMainThread {
                mainThreadCalls += 1
            }
            return calls
        }
        if duration > 0 {
            Thread.sleep(forTimeInterval: duration)
        }
        locked { inFlight -= 1 }
        if failingCalls.contains(index) {
            throw VisionError()
        }
        return ExtractedFeaturePrint(revision: revision, vector: vector)
    }

    /// Runs `body` while holding the lock.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

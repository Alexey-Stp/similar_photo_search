import Foundation

/// Limits how often progress is published: at most once per `interval`, unless an update is forced (phase changes,
/// the final snapshot).
public struct ScanProgressThrottle: Sendable {
    /// The shortest time between two published snapshots.
    public let interval: TimeInterval
    private var lastEmission: Date?

    /// Creates a throttle. The default allows 10 updates per second.
    public init(interval: TimeInterval = 0.1) {
        self.interval = max(0, interval)
    }

    /// Whether a snapshot may be published at `now`; records the emission if so. A forced snapshot is always allowed.
    public mutating func shouldEmit(at now: Date, force: Bool = false) -> Bool {
        if !force, let lastEmission, now.timeIntervalSince(lastEmission) < interval, now >= lastEmission {
            return false
        }
        lastEmission = now
        return true
    }
}

/// Estimates the time left from the average rate since the scan started.
public enum ScanETAEstimator {
    /// The shortest elapsed time before an estimate is given; earlier rates are noise.
    public static let minimumElapsed: TimeInterval = 1

    /// Seconds left to process `total - processed` photos at the rate seen since `startedAt`, or `nil` before there
    /// is enough data (nothing processed, or less than `minimumElapsed` elapsed). 0 when nothing is left.
    public static func eta(processed: Int, total: Int, startedAt: Date, now: Date) -> TimeInterval? {
        let remaining = max(0, total - processed)
        if remaining == 0, processed > 0 { return 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        guard processed > 0, elapsed >= minimumElapsed else { return nil }
        return elapsed / Double(processed) * Double(remaining)
    }
}

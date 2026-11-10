import Foundation

/// What the scan is doing.
public enum ScanPhase: Sendable, Hashable {
    /// Reading the library changes and listing photos; nothing is analysed yet.
    case enumerating
    /// Loading images and computing feature prints and quality measurements.
    case analyzing
    /// Grouping the photos of a session.
    case clustering
    /// Paused because the device is too hot (`ThermalLevel.critical`); it goes on by itself when it cools down.
    case throttled
    /// The scan finished; every result was published.
    case done
    /// The user (or the system) cancelled the scan. Results published so far stay valid and saved.
    case cancelled
    /// The scan stopped because of an error. Results published so far stay valid and saved.
    case failed(ScanFailure)

    /// Whether the scan has ended (done, cancelled or failed).
    public var isFinal: Bool {
        switch self {
        case .done, .cancelled, .failed: true
        case .enumerating, .analyzing, .clustering, .throttled: false
        }
    }
}

/// Why a scan stopped early.
public enum ScanFailure: Error, Sendable, Hashable {
    /// No similarity threshold is calibrated for this Vision revision (`ClusteringError.missingThreshold`). Shown as
    /// an error, never as "no duplicates found".
    case missingThreshold(revision: Int)
    /// The photo library could not be read.
    case libraryUnavailable
}

/// A snapshot of the scan's progress, published at most 10 times per second.
public struct ScanProgress: Sendable, Hashable {
    /// Photos handled so far: analysed, taken from the cache, skipped, or alone in their session.
    public var processed: Int
    /// Photos in the scope. An estimate while the scan runs (an upper bound with overlapping albums); equal to
    /// `processed` once the scan is done.
    public var total: Int
    /// Photos left out, per reason.
    public var skipped: [SkipReason: Int]
    /// Photos that Vision could not analyse (`AnalysisFailure`); they are left out of comparison.
    public var failed: Int
    /// What the scan is doing.
    public var phase: ScanPhase
    /// Estimated seconds until the scan is done, or `nil` while there is not enough data for an estimate.
    public var eta: TimeInterval?
    /// The device conditions the scan is adapting to (thermal state, Low Power Mode).
    public var conditions: ScanConditions
    /// Groups published so far in this scan.
    public var clusterCount: Int

    /// Creates a snapshot.
    public init(
        processed: Int = 0,
        total: Int = 0,
        skipped: [SkipReason: Int] = [:],
        failed: Int = 0,
        phase: ScanPhase = .enumerating,
        eta: TimeInterval? = nil,
        conditions: ScanConditions = .nominal,
        clusterCount: Int = 0
    ) {
        self.processed = processed
        self.total = total
        self.skipped = skipped
        self.failed = failed
        self.phase = phase
        self.eta = eta
        self.conditions = conditions
        self.clusterCount = clusterCount
    }

    /// `processed / total` in 0…1; 0 while the total is unknown.
    public var fractionCompleted: Double {
        guard total > 0 else { return phase == .done ? 1 : 0 }
        return min(1, max(0, Double(processed) / Double(total)))
    }

    /// The number of skipped photos over all reasons.
    public var skippedCount: Int {
        skipped.values.reduce(0, +)
    }
}

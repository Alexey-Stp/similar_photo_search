import Domain
import Foundation

/// `LibraryChangeTracker` that returns a scripted report and records the calls.
public actor MockLibraryChangeTracker: LibraryChangeTracker {
    /// What `changesSinceLastScan()` returns.
    public private(set) var report: LibraryChangeReport
    /// When set, `changesSinceLastScan()` throws it.
    public private(set) var error: (any Error)?
    /// How many times `changesSinceLastScan()` was called.
    public private(set) var changesCallCount = 0
    /// How many times `commitScanCompleted()` was called.
    public private(set) var commitCallCount = 0

    /// Creates the mock. By default it reports no changes.
    public init(report: LibraryChangeReport = .changes(LibraryDelta())) {
        self.report = report
    }

    /// Counts the call and returns `report`, or throws `error`.
    public func changesSinceLastScan() throws -> LibraryChangeReport {
        changesCallCount += 1
        if let error { throw error }
        return report
    }

    /// Counts the call.
    public func commitScanCompleted() {
        commitCallCount += 1
    }

    /// Replaces the report.
    public func setReport(_ report: LibraryChangeReport) {
        self.report = report
    }

    /// Sets or clears the error.
    public func setError(_ error: (any Error)?) {
        self.error = error
    }
}

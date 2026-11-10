import Domain
import Foundation
import Testing

struct ScanProgressTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func eta(processed: Int, total: Int, after seconds: TimeInterval) -> TimeInterval? {
        let now = start.addingTimeInterval(seconds)
        return ScanETAEstimator.eta(processed: processed, total: total, startedAt: start, now: now)
    }

    /// `#expect` can't wrap a mutating call.
    private func emit(_ throttle: inout ScanProgressThrottle, at date: Date, force: Bool = false) -> Bool {
        throttle.shouldEmit(at: date, force: force)
    }

    @Test func throttleAllowsAtMostOneSnapshotPerInterval() {
        var throttle = ScanProgressThrottle(interval: 0.1)
        #expect(emit(&throttle, at: start))
        #expect(!emit(&throttle, at: start.addingTimeInterval(0.05)))
        #expect(!emit(&throttle, at: start.addingTimeInterval(0.099)))
        #expect(emit(&throttle, at: start.addingTimeInterval(0.1)))
        #expect(!emit(&throttle, at: start.addingTimeInterval(0.15)))
    }

    @Test func forcedSnapshotsAlwaysPass() {
        var throttle = ScanProgressThrottle(interval: 0.1)
        #expect(emit(&throttle, at: start))
        #expect(emit(&throttle, at: start.addingTimeInterval(0.01), force: true))
        #expect(!emit(&throttle, at: start.addingTimeInterval(0.05)), "A forced snapshot restarts the interval")
    }

    @Test func aClockGoingBackwardsDoesNotBlockUpdates() {
        var throttle = ScanProgressThrottle(interval: 0.1)
        #expect(emit(&throttle, at: start))
        #expect(emit(&throttle, at: start.addingTimeInterval(-5)))
    }

    @Test func etaNeedsDataFirst() {
        #expect(eta(processed: 0, total: 100, after: 10) == nil)
        #expect(eta(processed: 10, total: 100, after: 0.5) == nil)
    }

    @Test func etaUsesTheAverageRate() {
        // 10 photos in 5 s → 2 photos/s → 90 left take 45 s.
        #expect(eta(processed: 10, total: 100, after: 5) == 45)
        #expect(eta(processed: 100, total: 100, after: 5) == 0)
    }

    @Test func recommendedConcurrencyFollowsTheConditions() {
        #expect(ScanConditions(thermalLevel: .nominal).recommendedConcurrency(fullConcurrency: 4) == 4)
        #expect(ScanConditions(thermalLevel: .fair).recommendedConcurrency(fullConcurrency: 4) == 4)
        #expect(ScanConditions(thermalLevel: .serious).recommendedConcurrency(fullConcurrency: 4) == 1)
        #expect(ScanConditions(thermalLevel: .critical).recommendedConcurrency(fullConcurrency: 4) == 0)
        #expect(ScanConditions(isLowPowerModeEnabled: true).recommendedConcurrency(fullConcurrency: 4) == 2)
        #expect(ScanConditions(isLowPowerModeEnabled: true).recommendedConcurrency(fullConcurrency: 1) == 1)
        #expect(
            ScanConditions(thermalLevel: .serious, isLowPowerModeEnabled: true)
                .recommendedConcurrency(fullConcurrency: 4) == 1
        )
        #expect(ScanConditions().recommendedConcurrency(fullConcurrency: 0) == 1)
        #expect(ScanConditions(thermalLevel: .critical).isPaused)
    }

    @Test func fractionCompletedIsClamped() {
        #expect(ScanProgress(processed: 5, total: 10).fractionCompleted == 0.5)
        #expect(ScanProgress(processed: 15, total: 10).fractionCompleted == 1)
        #expect(ScanProgress(processed: 0, total: 0).fractionCompleted == 0)
        #expect(ScanProgress(processed: 0, total: 0, phase: .done).fractionCompleted == 1)
        #expect(ScanProgress(skipped: [.iCloudOnly: 3, .noDate: 2]).skippedCount == 5)
    }

    @Test func resultsKeyChangesWithEverySetting() {
        let base = ScanResultsKey(
            sessionConfig: .default,
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.5]),
            revision: 2
        )
        let same = ScanResultsKey(
            sessionConfig: .default,
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.5]),
            revision: 2
        )
        #expect(base == same)
        #expect(base != ScanResultsKey(
            sessionConfig: SessionConfig(sessionGap: 60),
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.5]),
            revision: 2
        ))
        #expect(base != ScanResultsKey(
            sessionConfig: .default,
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.6]),
            revision: 2
        ))
        #expect(base != ScanResultsKey(
            sessionConfig: .default,
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.5]),
            revision: 1
        ))
        #expect(base != ScanResultsKey(
            sessionConfig: .default,
            clusteringConfig: ClusteringConfig(thresholds: [2: 0.5], maxChainSize: 20),
            revision: 2
        ))
    }
}

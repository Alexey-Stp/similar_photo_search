import Domain
import DomainTestSupport
import Foundation
import Testing

/// Cancel, restart, and photos deleted while a scan runs.
struct AnalysisCoordinatorCancellationTests {
    typealias Fixture = ScanFixture

    // MARK: - Cancellation

    /// Cancel stops the scan within 500 ms; prints finished before it are saved; nothing is committed.
    @Test func cancelStopsWithin500msAndKeepsFinishedWork() async throws {
        let service = ScriptedFeaturePrintService(prints: Fixture.prints, blocked: ["s3-b"])
        let harness = ScanHarness(
            assets: Fixture.library,
            service: service,
            settings: AnalysisCoordinator.Settings(fullConcurrency: 2, progressInterval: 0)
        )
        let streams = await harness.start()
        let collected = Task { await Fixture.collect(streams) }
        #expect(await eventually { service.requestedIDs.contains("s3-b") && service.requestedIDs.contains("s3-a") })
        try await Task.sleep(for: .milliseconds(20))

        let clock = ContinuousClock()
        let started = clock.now
        await harness.coordinator.cancel()
        let (updates, progress) = await collected.value
        let elapsed = clock.now - started

        #expect(elapsed < .milliseconds(500))
        #expect(progress.last?.phase == .cancelled)
        #expect(updates == [.finished])
        #expect(await harness.cache.cachedAssetIDs() == ["s3-a"], "The finished print is saved")
        #expect(await harness.tracker.commitCallCount == 0)
        #expect(!service.requestedIDs.contains("s2-a"))
    }

    /// After a cancelled scan, a new scan only analyses what was left.
    @Test func aScanAfterACancelOnlyAnalysesTheRest() async throws {
        let blocking = ScriptedFeaturePrintService(prints: Fixture.prints, blocked: ["s2-a", "s2-b"])
        let first = ScanHarness(assets: Fixture.library, service: blocking)
        let streams = await first.start()
        let collected = Task { await Fixture.collect(streams) }
        #expect(await eventually { blocking.requestedIDs.contains("s2-a") })
        await first.coordinator.cancel()
        let (firstUpdates, _) = await collected.value
        #expect(Fixture.addedIDs(firstUpdates) == ["s3-b"])

        let second = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            cache: first.cache,
            results: first.results
        )
        let (updates, _) = await second.scan()
        #expect(Set(second.service.requestedIDs) == ["s2-a", "s2-b", "s1-a", "s1-b"])
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// Starting a new scan cancels the running one; the new scan runs to the end.
    @Test func startingAgainCancelsTheRunningScan() async {
        let service = ScriptedFeaturePrintService(prints: Fixture.prints, blocked: ["s3-a"])
        let harness = ScanHarness(assets: Fixture.library, service: service)
        let firstStreams = await harness.start()
        let first = Task { await Fixture.collect(firstStreams) }
        #expect(await eventually { service.requestedIDs.contains("s3-a") })

        let secondStreams = await harness.start()
        service.unblock(["s3-a"])
        let (_, firstProgress) = await first.value
        let (secondUpdates, secondProgress) = await Fixture.collect(secondStreams)
        #expect(firstProgress.last?.phase == .cancelled)
        #expect(secondProgress.last?.phase == .done)
        #expect(Fixture.addedIDs(secondUpdates) == ["s3-b", "s2-b", "s1-b"])
    }

    // MARK: - Deleted during the scan

    /// Photos deleted while the scan runs are never loaded, analysed or published.
    @Test func photosDeletedDuringTheScanAreNeverAnalysed() async {
        let service = ScriptedFeaturePrintService(prints: Fixture.prints, blocked: ["s3-a"])
        let harness = ScanHarness(assets: Fixture.library, service: service)
        let streams = await harness.start()
        let collected = Task { await Fixture.collect(streams) }
        #expect(await eventually { service.requestedIDs.contains("s3-a") })

        await harness.coordinator.excludeDeleted(["s2-a", "s1-b"])
        service.unblock(["s3-a"])
        let (updates, progress) = await collected.value

        #expect(!service.requestedIDs.contains("s2-a"))
        #expect(!service.requestedIDs.contains("s1-b"))
        #expect(Fixture.addedIDs(updates) == ["s3-b"])
        #expect(progress.last?.phase == .done)
    }
}

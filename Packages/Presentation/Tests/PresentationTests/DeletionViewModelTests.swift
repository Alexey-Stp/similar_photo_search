import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// The deletion flow: review, deleting, result and the cleanup after it (SPS-25).
@MainActor
struct DeletionViewModelTests {
    private static let megabyte: Int64 = 1_000_000

    /// Group A keeps A1 and selects A2, A3; group B keeps B1 and selects B2.
    private func makeHarness() -> DeletionHarness {
        let sizes = Dictionary(uniqueKeysWithValues: ["A2", "A3", "B2"].map { ($0, Self.megabyte) })
        let harness = DeletionHarness(sizes: sizes)
        harness.show([["A1", "A2", "A3"], ["B1", "B2"]])
        return harness
    }

    // MARK: - Review

    @Test func theReviewShowsCountSizeAndGroupsAndDeletesNothing() async {
        let harness = makeHarness()
        let service = MockAssetDeletionService()
        let flow = harness.makeFlow(service)
        await harness.store.waitForSizeEstimate()

        #expect(flow.state == .review)
        #expect(flow.assetIDs == ["A2", "A3", "B2"])
        #expect(flow.summary.photoCount == 3)
        #expect(flow.summary.estimatedBytes == 3 * Self.megabyte)
        #expect(flow.groupCount == 2)
        #expect(!flow.isDismissDisabled)
        #expect(await service.deletionRequests.isEmpty)
    }

    // MARK: - Deleting

    @Test func theFlowIsDeletingAndCantBeDismissedUntilTheAlertIsAnswered() async {
        let harness = makeHarness()
        let service = GatedDeletionService()
        let flow = harness.makeFlow(service)

        let confirming = Task { await flow.confirm() }
        #expect(await harness.eventually { flow.state == .deleting })
        #expect(flow.isDismissDisabled)
        #expect(harness.lifecycle.begun == ["SimilarPhotos.delete"])
        #expect(harness.scan.isOwnDeletionInProgress)

        await flow.confirm()
        #expect(await service.waitingCount == 1, "A second tap asks the system only once")

        await service.release(with: DeletionResult(deleted: ["A2", "A3", "B2"]))
        await confirming.value
        guard case .success = flow.state else {
            Issue.record("Expected success, got \(flow.state)")
            return
        }
        #expect(!flow.isDismissDisabled)
        #expect(harness.lifecycle.ended.count == 1)
    }

    // MARK: - Success

    @Test func successPurgesTheCacheUpdatesTheGroupsAndExcludesThePhotosFromTheScan() async throws {
        let harness = makeHarness()
        let flow = harness.makeFlow(MockAssetDeletionService())
        await harness.store.waitForSizeEstimate()

        await flow.confirm()

        guard case .success(let outcome) = flow.state else {
            Issue.record("Expected success, got \(flow.state)")
            return
        }
        #expect(outcome.deletedCount == 3)
        #expect(outcome.requestedCount == 3)
        #expect(outcome.freed.estimatedBytes == 3 * Self.megabyte)
        #expect(outcome.failures.isEmpty)
        #expect(Set(await harness.cache.purgedIDs) == ["A2", "A3", "B2"])
        #expect(await harness.coordinator.excludedIDs == [["A2", "A3", "B2"]])
        // Both groups are left with one photo, so both are gone; nothing stays selected.
        #expect(harness.store.clusterIDs.isEmpty)
        #expect(harness.store.selectedCount == 0)
        #expect(harness.scan.rowOrder.ids.isEmpty)
        #expect(await harness.coordinator.startCalls.isEmpty, "No rescan")
    }

    @Test func aFailedPurgeStillShowsTheResult() async {
        let harness = makeHarness()
        await harness.cache.setWriteError(CocoaError(.fileWriteUnknown))
        let flow = harness.makeFlow(MockAssetDeletionService())

        await flow.confirm()

        guard case .success = flow.state else {
            Issue.record("Expected success, got \(flow.state)")
            return
        }
        #expect(harness.store.clusterIDs.isEmpty)
    }

    // MARK: - Cancel

    @Test func aUserCancelReturnsToTheReviewAndChangesNothing() async {
        let harness = makeHarness()
        let flow = harness.makeFlow(MockAssetDeletionService(result: DeletionResult(cancelled: true)))
        let revision = harness.scan.clusterRevision

        await flow.confirm()

        #expect(flow.state == .review)
        #expect(flow.assetIDs == ["A2", "A3", "B2"])
        #expect(harness.store.selectedAssetIDs == ["A2", "A3", "B2"])
        #expect(harness.scan.clusterRevision == revision)
        #expect(await harness.cache.purgedIDs.isEmpty)
        #expect(await harness.coordinator.excludedIDs.isEmpty)
        #expect(harness.lifecycle.ended.count == 1)
    }

    @Test func aCancelAfterAnEarlierChunkProcessesItsDeletionsAndReviewsTheRest() async {
        let harness = makeHarness()
        let result = DeletionResult(deleted: ["B2"], cancelled: true)
        let flow = harness.makeFlow(MockAssetDeletionService(result: result))

        await flow.confirm()

        #expect(flow.state == .review)
        #expect(flow.assetIDs == ["A2", "A3"])
        #expect(await harness.cache.purgedIDs == ["B2"])
        #expect(await harness.coordinator.excludedIDs == [["B2"]])
        #expect(harness.store.clusterIDs == ["A1"])
        #expect(harness.store.selectedAssetIDs == ["A2", "A3"])
    }

    // MARK: - Partial failure

    @Test func photosThatCouldNotBeDeletedStayInTheirGroupAndSelected() async {
        let harness = DeletionHarness()
        harness.show([["A1", "A2", "A3", "A4"]])
        let result = DeletionResult(deleted: ["A2"], failed: ["A3": .notDeletable, "A4": .notDeletable])
        let flow = harness.makeFlow(MockAssetDeletionService(result: result))

        await flow.confirm()

        guard case .partial(let outcome) = flow.state else {
            Issue.record("Expected a partial result, got \(flow.state)")
            return
        }
        #expect(outcome.deletedCount == 1)
        #expect(outcome.requestedCount == 3)
        #expect(outcome.failures.map(\.id) == ["A3", "A4"])
        #expect(outcome.failures.allSatisfy { $0.reason == .notDeletable })
        #expect(harness.store.state(for: "A1")?.memberIDs == ["A1", "A3", "A4"])
        #expect(harness.store.selectedAssetIDs == ["A3", "A4"])
        #expect(await harness.cache.purgedIDs == ["A2"])
    }

    @Test func aPhotoMissingFromTheResultCountsAsNotDeleted() async {
        let harness = makeHarness()
        let flow = harness.makeFlow(MockAssetDeletionService(result: DeletionResult(deleted: ["A2", "A3"])))

        await flow.confirm()

        guard case .partial(let outcome) = flow.state else {
            Issue.record("Expected a partial result, got \(flow.state)")
            return
        }
        #expect(outcome.failures == [DeletionOutcome.Failure(id: "B2", reason: .notDeleted)])
    }

    // MARK: - Lost access

    @Test func lostAccessFailsWithAMessageAndChangesNothing() async {
        let harness = makeHarness()
        let ids = ["A2", "A3", "B2"]
        let flow = harness.makeFlow(MockAssetDeletionService(result: .permissionDenied(for: ids)))

        await flow.confirm()

        guard case .failed = flow.state else {
            Issue.record("Expected a failure, got \(flow.state)")
            return
        }
        #expect(harness.store.selectedAssetIDs == ids)
        #expect(await harness.cache.purgedIDs.isEmpty)
        #expect(await harness.coordinator.excludedIDs.isEmpty)
    }

    // MARK: - Photos app

    @Test func openPhotosIsOfferedOnlyWhenTheSystemCanOpenIt() {
        let harness = makeHarness()
        let flow = harness.makeFlow(MockAssetDeletionService())
        #expect(flow.canOpenPhotos)
        flow.openPhotos()
        #expect(harness.photosApp.openCount == 1)

        harness.photosApp.canOpenPhotos = false
        #expect(!flow.canOpenPhotos)
    }
}

extension DeletionHarness {
    /// Polls on the main actor until `condition` holds (up to 2 s).
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }
}

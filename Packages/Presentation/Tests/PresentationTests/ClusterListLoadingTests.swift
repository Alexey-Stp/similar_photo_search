import CoreGraphics
import Domain
import DomainTestSupport
import Foundation
@testable import Presentation
import Testing

/// Dates, missing photos, the prefetch window and the list's texts.
@MainActor
struct ClusterListLoadingTests {
    private typealias Harness = ClusterListHarness

    // MARK: - Dates and availability

    @Test func cardsGetTheDatesOfTheirPhotos() async throws {
        let harness = Harness(photos: ["A1": 2_000, "A2": 1_000])
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"])])
        let card = try #require(harness.list.card(for: "A1"))
        #expect(card.photos.map(\.date) == [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
        #expect(card.date == Date(timeIntervalSince1970: 2_000), "The header shows the newest photo")
        #expect(card.photos.allSatisfy { !$0.isMissing })
    }

    @Test func aPhotoDeletedOutsideTheAppGetsAPlaceholder() async throws {
        let harness = Harness(photos: ["A1": 2_000, "A2": 1_000])
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"])])
        let observing = Task { await harness.list.observeLibraryChanges() }
        _ = await harness.eventually { harness.changes.changesCallCount == 1 }

        await harness.library.setAssets([Harness.asset("A1", 2_000)])
        harness.changes.signal()
        _ = await harness.eventually { harness.list.missingAssetIDs == ["A2"] }
        await harness.list.waitForLoads()
        let card = try #require(harness.list.card(for: "A1"))
        #expect(card.photos.map(\.isMissing) == [false, true])

        harness.list.toggle("A2", in: "A1")
        #expect(harness.list.selection.isSelected("A2"), "A missing photo can't be toggled")
        observing.cancel()
    }

    @Test func aDeleteRequestLeavesOutPhotosThatNoLongerExist() async {
        let harness = Harness(photos: ["A1": 3_000, "A2": 2_000, "A3": 1_000])
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2", "A3"])])
        let observing = Task { await harness.list.observeLibraryChanges() }
        _ = await harness.eventually { harness.changes.changesCallCount == 1 }

        await harness.library.setAssets([Harness.asset("A1", 3_000), Harness.asset("A2", 2_000)])
        harness.changes.signal()
        _ = await harness.eventually { harness.list.missingAssetIDs == ["A3"] }
        harness.list.requestDeletion()
        #expect(harness.list.deletionRequest?.assetIDs == ["A2"])
        observing.cancel()
    }

    // MARK: - Prefetch window

    @Test func prefetchCoversTenRowsAroundTheRowThatAppeared() async {
        let harness = Harness()
        let groups = (0..<30).map { Harness.group(["G\($0)a", "G\($0)b"]) }
        await harness.scan.startScan()
        await harness.publish(groups)
        harness.list.displayScaleChanged(2)

        harness.list.rowAppeared("G0a")
        await harness.list.waitForLoads()
        let first = Set(harness.thumbnails.prefetched.last ?? [])
        #expect(first.count == 22, "Rows 0…10, two photos each")
        #expect(first.contains("G10b") && !first.contains("G11a"))
        #expect(harness.thumbnails.prefetchSizes.last == CGSize(width: 176, height: 176))

        harness.list.rowAppeared("G15a")
        await harness.list.waitForLoads()
        #expect(Set(harness.thumbnails.stopped.last ?? []) == Set((0..<5).flatMap { ["G\($0)a", "G\($0)b"] }))
        #expect(Set(harness.thumbnails.prefetched.last ?? []) == Set((11...25).flatMap { ["G\($0)a", "G\($0)b"] }))

        harness.list.stopPrefetching()
        await harness.list.waitForLoads()
        #expect(harness.thumbnails.stopAllCalls >= 1)
    }

    // MARK: - Text

    @Test func theThumbnailLabelReadsPositionDateStatusAndBest() {
        let label = ClusterCardModel.photoAccessibilityLabel(
            position: 2,
            count: 5,
            dateText: "12 May 14:03",
            status: .selected,
            isBest: true
        )
        #expect(label == "Photo 2 of 5, taken 12 May 14:03, selected for deletion, Best shot")

        let kept = ClusterCardModel.photoAccessibilityLabel(
            position: 1,
            count: 2,
            dateText: nil,
            status: .kept,
            isBest: false
        )
        #expect(kept == "Photo 1 of 2, kept")
    }

    @Test func theDeleteButtonNamesCountAndSize() {
        let known = DeletionSummary(photoCount: 3, knownBytes: 3_000_000, unavailableCount: 0, pendingCount: 0)
        #expect(SelectionSummaryBar.deleteTitle(for: known).hasPrefix("Delete 3 photos ("))
        let estimating = DeletionSummary(photoCount: 1, knownBytes: 0, unavailableCount: 0, pendingCount: 1)
        #expect(SelectionSummaryBar.deleteTitle(for: estimating) == "Delete 1 photo")
        #expect(SelectionSummaryBar.deleteTitle(for: .empty) == "Delete 0 photos")
    }
}

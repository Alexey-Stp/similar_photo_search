import CoreGraphics
import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// `ScreenImageLoading` fake: no image; records the requested sizes.
final class MockScreenImageLoader: ScreenImageLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [CGSize] = []

    /// Pixel sizes requested so far.
    var requestedSizes: [CGSize] {
        lock.withLock { sizes }
    }

    /// Records the size; returns no image.
    func screenImage(for assetID: String, pixelSize: CGSize) async -> ScreenImage? {
        lock.withLock { sizes.append(pixelSize) }
        return nil
    }
}

/// The comparison of one group (SPS-22): what is shown, which images are held, details and actions.
@MainActor
struct PhotoComparisonViewModelTests {
    private typealias Harness = ClusterListHarness

    /// A group A1…A4 whose suggestion keeps `A2` and deletes A3 and A4, with reasons on A2 and A3.
    private func makeComparison(
        harness: Harness = Harness(),
        edited: Set<String> = []
    ) -> PhotoComparisonViewModel {
        let ids = ["A1", "A2", "A3", "A4"]
        harness.scan.showStoredResults([
            ClusterSelection(
                cluster: SimilarityCluster(id: "G", assetIDs: ids, suggestedKeeperID: "A2"),
                ranking: [
                    RankedMember(assetID: "A2", score: 1, isProtected: true, reasons: [.favorite, .sharpest]),
                    RankedMember(assetID: "A3", score: 0.5, isProtected: false, reasons: [.highestResolution])
                ],
                suggestedForDeletion: ["A3", "A4"],
                needsReview: false
            )
        ])
        return PhotoComparisonViewModel(
            clusterID: "G",
            list: harness.list,
            screenImages: MockScreenImageLoader(),
            edits: MockPhotoEditStatusProvider(edited: edited)
        )
    }

    // MARK: - What is shown

    @Test func thePagerStartsOnTheBestPhotoAndPairsItWithTheNextOne() {
        let comparison = makeComparison()
        #expect(comparison.shownCurrentID == "A2")
        #expect(comparison.shownSecondaryID == "A3")
        comparison.currentID = "A4"
        #expect(comparison.shownSecondaryID == "A2", "Any other photo is compared with the Best")
    }

    @Test func onlyTheCurrentPhotoAndItsNeighboursHoldAFullImage() {
        let comparison = makeComparison()
        comparison.currentID = "A1"
        #expect(comparison.memberIDs.filter(comparison.shouldLoadFullImage) == ["A1", "A2"])
        comparison.currentID = "A3"
        #expect(comparison.memberIDs.filter(comparison.shouldLoadFullImage) == ["A2", "A3", "A4"])
    }

    @Test func sideBySideHoldsOnlyTheTwoShownPhotos() {
        let comparison = makeComparison()
        comparison.layoutChanged(canShowSideBySide: true)
        #expect(comparison.showsSideBySide)
        #expect(comparison.memberIDs.filter(comparison.shouldLoadFullImage) == ["A2", "A3"])

        comparison.prefersSideBySide = false
        #expect(!comparison.showsSideBySide)
    }

    @Test func theFilmstripFillsTheFocusedPaneAndSwapsDuplicates() {
        let comparison = makeComparison()
        comparison.layoutChanged(canShowSideBySide: true)
        comparison.focus(.secondary)
        comparison.show("A4")
        #expect(comparison.shownCurrentID == "A2")
        #expect(comparison.shownSecondaryID == "A4")
        #expect(comparison.focusedID == "A4")

        comparison.show("A2")
        #expect(comparison.shownCurrentID == "A4")
        #expect(comparison.shownSecondaryID == "A2")
    }

    @Test func changingThePageResetsItsZoom() {
        let comparison = makeComparison()
        comparison.pagerZoom.magnify(by: 2, content: CGSize(width: 100, height: 100))
        comparison.currentID = "A3"
        #expect(!comparison.pagerZoom.isZoomed)
    }

    @Test func aGroupThatIsGoneIsNotAvailable() async {
        let harness = Harness()
        let comparison = makeComparison(harness: harness)
        harness.scan.selection.remove(clusterIDs: ["G"])
        #expect(!comparison.isAvailable)
        #expect(comparison.shownCurrentID == nil)
    }

    // MARK: - Details

    @Test func detailsCombineLibrarySizesEditsAndReasons() async throws {
        let harness = Harness(sizes: ["A2": 3_000_000])
        await harness.library.setAssets([
            PhotoAsset(
                id: "A2",
                creationDate: Date(timeIntervalSince1970: 1_000),
                pixelWidth: 4_032,
                pixelHeight: 3_024,
                isFavorite: true,
                mediaSubtypes: [.livePhoto]
            )
        ])
        let comparison = makeComparison(harness: harness, edited: ["A2"])
        await comparison.loadDetails()

        let info = comparison.info(for: "A2")
        #expect(info.date == Date(timeIntervalSince1970: 1_000))
        #expect(info.pixelWidth == 4_032)
        #expect(info.fileSize == 3_000_000)
        #expect(info.isFavorite && info.isEdited && info.isLivePhoto)
        #expect(info.reasons == [.sharpest], "Favorite is a badge, not repeated as a reason")
        #expect(comparison.info(for: "A3").reasons == [.highestResolution])
        #expect(comparison.isMissing("A1"), "Photos the library no longer has are missing")
    }

    // MARK: - Actions

    @Test func keepThisOneSelectsEveryOtherExistingPhoto() async {
        let harness = Harness()
        await harness.library.setAssets(["A1", "A2", "A3"].map { Harness.asset($0, 0) })
        let comparison = makeComparison(harness: harness)
        await comparison.loadDetails()

        comparison.keepOnly("A1")
        #expect(comparison.selection.selectedAssetIDs == ["A2", "A3"], "A4 no longer exists and is not selected")
        #expect(comparison.isBest("A1"))
    }

    @Test func markAsBestAndToggleApplyToTheStoreAtOnce() {
        let comparison = makeComparison()
        comparison.markAsBest("A3")
        #expect(comparison.isBest("A3"))
        #expect(!comparison.isSelected("A3"))

        comparison.toggle("A1")
        #expect(comparison.selection.isSelected("A1"))
    }

    @Test func selectingTheLastKeptPhotoAsksFirst() {
        let comparison = makeComparison()
        comparison.keepOnly("A2")
        comparison.toggle("A2")
        #expect(comparison.isConfirmingDeleteAll)
        #expect(!comparison.isSelected("A2"))

        comparison.confirmDeleteAll()
        #expect(comparison.isSelected("A2"))
        #expect(!comparison.isConfirmingDeleteAll)
    }

    @Test func missingPhotosCantBeChosen() async {
        let harness = Harness()
        await harness.library.setAssets(["A2", "A3", "A4"].map { Harness.asset($0, 0) })
        let comparison = makeComparison(harness: harness)
        await comparison.loadDetails()

        comparison.toggle("A1")
        comparison.markAsBest("A1")
        comparison.keepOnly("A1")
        #expect(!comparison.isSelected("A1"))
        #expect(comparison.isBest("A2"))
        #expect(comparison.selection.selectedAssetIDs == ["A3", "A4"])
    }
}

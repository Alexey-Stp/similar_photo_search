import CoreGraphics
import DataLayer
import Foundation
import Photos
import Testing

/// Screen-size images for the comparison (SPS-22): local only, capped size, iCloud fallback, cancellation.
struct PhotoKitScreenImageLoaderTests {
    private let size = CGSize(width: 1_170, height: 2_532)

    /// An empty "only in iCloud" answer, as `.highQualityFormat` gives without network access.
    private let inCloud = ImageRequestResult(isInCloud: true)

    // MARK: - Options and size

    @Test func originalsAreHighQualityExactAndLocalOnly() {
        let options = PhotoKitScreenImageRequester.makeOptions(for: .original)
        #expect(options.isNetworkAccessAllowed == false)
        #expect(options.deliveryMode == .highQualityFormat)
        #expect(options.resizeMode == .exact)
        #expect(options.version == .current)
        #expect(PhotoKitScreenImageRequester.contentMode == .aspectFit)
    }

    @Test func localPreviewsAreOpportunisticAndLocalOnly() {
        let options = PhotoKitScreenImageRequester.makeOptions(for: .localPreview)
        #expect(options.isNetworkAccessAllowed == false)
        #expect(options.deliveryMode == .opportunistic)
    }

    @Test func sizesAreCappedAndNeverTheMaximumSize() {
        let maxSide = PhotoKitScreenImageLoader.maxPixelSide
        let capped = PhotoKitScreenImageLoader.cappedSize
        #expect(capped(PHImageManagerMaximumSize) == CGSize(width: maxSide, height: maxSide))
        #expect(capped(CGSize(width: 12_000, height: 0.2)) == CGSize(width: maxSide, height: 1))
        #expect(capped(CGSize(width: 1_170.4, height: .nan)) == CGSize(width: 1_170, height: maxSide))
    }

    @Test func theRequestedSizeIsCapped() async throws {
        let original = MockImageRequester(defaultBehavior: .respond([try ImageTestSupport.success()]))
        let preview = MockImageRequester(defaultBehavior: .missing)
        let loader = PhotoKitScreenImageLoader(original: original, preview: preview)
        _ = await loader.screenImage(for: "A", size: CGSize(width: 9_000, height: 6_000))
        #expect(original.requestedSizes == [CGSize(width: 4_096, height: 4_096)])
    }

    // MARK: - Outcomes

    @Test func aLocalOriginalIsReturnedWithoutAskingForThePreview() async throws {
        let original = MockImageRequester(defaultBehavior: .respond([try ImageTestSupport.success()]))
        let preview = MockImageRequester(defaultBehavior: .respond([try ImageTestSupport.success()]))
        let loader = PhotoKitScreenImageLoader(original: original, preview: preview)

        guard case .original = await loader.screenImage(for: "A", size: size) else {
            Issue.record("expected the original")
            return
        }
        #expect(original.requestedSizes == [size])
        #expect(preview.requestedAssetIDs.isEmpty)
    }

    @Test func anICloudOnlyOriginalFallsBackToTheLocalPreview() async throws {
        var degraded = try ImageTestSupport.success()
        degraded.isDegraded = true
        // `.opportunistic` without network: the local degraded image, then an empty final "in cloud" answer.
        let original = MockImageRequester(defaultBehavior: .respond([inCloud]))
        let preview = MockImageRequester(defaultBehavior: .respond([degraded, inCloud]))
        let loader = PhotoKitScreenImageLoader(original: original, preview: preview)

        guard case .localPreview = await loader.screenImage(for: "A", size: size) else {
            Issue.record("expected the local preview")
            return
        }
        #expect(preview.requestedAssetIDs == ["A"])
    }

    @Test func anICloudOnlyOriginalWithoutAnyLocalImageIsUnavailable() async {
        let original = MockImageRequester(defaultBehavior: .respond([inCloud]))
        let preview = MockImageRequester(defaultBehavior: .respond([inCloud]))
        let loader = PhotoKitScreenImageLoader(original: original, preview: preview)
        guard case .unavailable = await loader.screenImage(for: "A", size: size) else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func aMissingOrBrokenPhotoIsUnavailableWithoutAPreview() async {
        let original = MockImageRequester(
            defaultBehavior: .missing,
            behaviors: ["broken": .respond([ImageRequestResult(hasError: true)])]
        )
        let preview = MockImageRequester(defaultBehavior: .respond([inCloud]))
        let loader = PhotoKitScreenImageLoader(original: original, preview: preview)

        for assetID in ["gone", "broken"] {
            guard case .unavailable = await loader.screenImage(for: assetID, size: size) else {
                Issue.record("expected unavailable for \(assetID)")
                return
            }
        }
        #expect(preview.requestedAssetIDs.isEmpty)
    }

    @Test func cancellingTheTaskCancelsTheRequest() async throws {
        let original = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitScreenImageLoader(original: original, preview: MockImageRequester(defaultBehavior: .hold))
        let task = Task { await loader.screenImage(for: "A", size: size) }
        #expect(await ImageTestSupport.waitUntil { original.heldCount == 1 })

        task.cancel()
        guard case .unavailable = await task.value else {
            Issue.record("expected unavailable after cancellation")
            return
        }
        #expect(original.allHeldRequestsCancelled)
        // A late callback after the cancellation is ignored.
        original.releaseAllHeld(with: try ImageTestSupport.success())
    }
}

/// `AssetEditInspecting` fake: a fixed answer per photo, `nil` for unknown ones.
private struct FakeEditInspector: AssetEditInspecting {
    let answers: [String: Bool]

    func isEdited(assetID: String) -> Bool? {
        answers[assetID]
    }
}

struct PhotoKitEditStatusProviderTests {
    @Test func onlyEditedExistingPhotosAreReturned() async {
        let provider = PhotoKitEditStatusProvider(inspector: FakeEditInspector(answers: ["A": true, "B": false]))
        #expect(await provider.editedAssetIDs(among: ["A", "B", "gone"]) == ["A"])
    }
}

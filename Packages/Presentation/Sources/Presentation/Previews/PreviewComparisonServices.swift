#if DEBUG
import Domain
import SwiftUI

/// `ScreenImageLoading` for previews: the preview thumbnail symbol at up to 600 px. Photos whose ID ends in "3"
/// pretend their original is in iCloud.
struct PreviewScreenImageLoader: ScreenImageLoading {
    /// The rendered symbol, flagged "Original in iCloud" for IDs ending in "3".
    func screenImage(for assetID: String, pixelSize: CGSize) async -> ScreenImage? {
        let side = min(pixelSize.width, pixelSize.height, 600)
        let images = PreviewThumbnailLoader().thumbnail(for: assetID, pixelSize: CGSize(width: side, height: side))
        for await image in images {
            return ScreenImage(image: image, isOriginalInCloud: assetID.hasSuffix("3"))
        }
        return nil
    }
}

/// `PhotoEditStatusProviding` for previews: photos whose ID ends in "2" are edited.
struct PreviewEditStatusProvider: PhotoEditStatusProviding {
    /// The IDs ending in "2".
    func editedAssetIDs(among assetIDs: [String]) async -> Set<String> {
        Set(assetIDs.filter { $0.hasSuffix("2") })
    }
}

extension PhotoComparisonViewModel {
    /// The comparison of the first preview group ("A1", "A2", "A3"), with reasons on its photos.
    static func preview(clusterID: String = "A1") -> PhotoComparisonViewModel {
        let list = ClusterListViewModel.preview()
        list.selection.upsert([
            ClusterSelection(
                cluster: SimilarityCluster(assetIDs: ["A1", "A2", "A3"], suggestedKeeperID: "A1"),
                ranking: [
                    RankedMember(assetID: "A1", score: 0.9, isProtected: false, reasons: [.sharpest, .bestFaces]),
                    RankedMember(assetID: "A2", score: 0.6, isProtected: false, reasons: [.highestResolution]),
                    RankedMember(assetID: "A3", score: 0.2, isProtected: false, reasons: [])
                ],
                suggestedForDeletion: ["A2", "A3"],
                needsReview: false
            )
        ])
        return PhotoComparisonViewModel(
            clusterID: clusterID,
            list: list,
            screenImages: PreviewScreenImageLoader(),
            edits: PreviewEditStatusProvider()
        )
    }
}

#Preview("Pager") {
    PhotoComparisonScreen(viewModel: .preview())
}

#Preview("Side by side", traits: .landscapeLeft) {
    PhotoComparisonScreen(viewModel: .preview())
}

#Preview("Review group, AX5") {
    PhotoComparisonScreen(viewModel: .preview(clusterID: "B1"))
        .dynamicTypeSize(.accessibility5)
}
#endif

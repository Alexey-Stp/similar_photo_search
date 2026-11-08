import Domain
import Foundation
import Testing

struct EntityTests {
    private func makeAsset(id: String = "A", isFavorite: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: 4032,
            pixelHeight: 3024,
            isFavorite: isFavorite,
            mediaSubtypes: [.hdr, .livePhoto]
        )
    }

    @Test func photoAssetsWithSameValuesAreEqual() {
        #expect(makeAsset() == makeAsset())
        #expect(Set([makeAsset(), makeAsset()]).count == 1)
    }

    @Test func photoAssetsWithDifferentValuesAreNotEqual() {
        #expect(makeAsset(id: "A") != makeAsset(id: "B"))
        #expect(makeAsset(isFavorite: true) != makeAsset(isFavorite: false))
    }

    @Test func photoAssetIdentityIsLocalIdentifier() {
        #expect(makeAsset(id: "local-id/L0/001").id == "local-id/L0/001")
    }

    @Test func clusterDefaultsToNoSuggestedKeeper() {
        let cluster = SimilarityCluster(assetIDs: ["A", "B"])
        #expect(cluster.suggestedKeeperID == nil)
        #expect(cluster.assetIDs == ["A", "B"])
    }

    @Test func featurePrintsOfSameRevisionAndLengthAreComparable() {
        let lhs = FeaturePrint(assetID: "A", revision: 2, vector: [0, 1, 2], assetModificationDate: nil)
        let rhs = FeaturePrint(assetID: "B", revision: 2, vector: [2, 1, 0], assetModificationDate: nil)
        #expect(lhs.isComparable(with: rhs))
    }

    @Test func featurePrintsOfDifferentRevisionsAreNeverComparable() {
        let lhs = FeaturePrint(assetID: "A", revision: 1, vector: [0, 1, 2], assetModificationDate: nil)
        let rhs = FeaturePrint(assetID: "B", revision: 2, vector: [0, 1, 2], assetModificationDate: nil)
        #expect(!lhs.isComparable(with: rhs))
    }

    @Test func featurePrintsOfDifferentLengthsAreNotComparable() {
        let lhs = FeaturePrint(assetID: "A", revision: 2, vector: [0, 1], assetModificationDate: nil)
        let rhs = FeaturePrint(assetID: "B", revision: 2, vector: [0, 1, 2], assetModificationDate: nil)
        #expect(!lhs.isComparable(with: rhs))
    }

    @Test func entitiesAreSendable() {
        requireSendable(PhotoAsset.self)
        requireSendable(PhotoSubtype.self)
        requireSendable(SimilarityCluster.self)
        requireSendable(FeaturePrint.self)
        requireSendable(PhotoLibraryAuthorization.self)
        requireSendable(DeletionOutcome.self)
    }

    private func requireSendable<T: Sendable>(_ type: T.Type) {}
}

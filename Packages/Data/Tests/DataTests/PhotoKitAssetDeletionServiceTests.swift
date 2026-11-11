@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing

/// Deletion outcomes over a scripted library: success, user cancel, missing and non-deletable assets, lost access.
struct PhotoKitAssetDeletionServiceTests {
    /// A service over `library` with the chunked fallback off.
    private func makeService(_ library: FakePhotoLibraryPerformer) -> PhotoKitAssetDeletionService {
        PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: nil)
    }

    @Test func deletesEveryDeletableAssetInOneRequest() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C"])
        let result = await makeService(library).delete(assetIDs: ["A", "B", "C"])
        #expect(result == DeletionResult(deleted: ["A", "B", "C"]))
        #expect(library.deleteRequests == [["A", "B", "C"]])
    }

    @Test func missingAssetsAreUnavailableAndNotRequested() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A"])
        let result = await makeService(library).delete(assetIDs: ["A", "gone"])
        #expect(result == DeletionResult(deleted: ["A"], failed: ["gone": .unavailable]))
        #expect(library.deleteRequests == [["A"]])
    }

    @Test func nonDeletableAssetsAreExcludedFromTheRequest() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "C"], notDeletable: ["shared"])
        let result = await makeService(library).delete(assetIDs: ["A", "shared", "C"])
        #expect(result == DeletionResult(deleted: ["A", "C"], failed: ["shared": .notDeletable]))
        #expect(library.deleteRequests == [["A", "C"]])
        #expect(library.assets["shared"] == false)
    }

    @Test func userCancelChangesNothingAndIsNotAnError() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"], notDeletable: ["shared"])
        library.responses = [FakePhotoLibraryPerformer.photosError(.userCancelled)]
        let result = await makeService(library).delete(assetIDs: ["A", "B", "shared"])
        #expect(result == DeletionResult(failed: ["shared": .notDeletable], cancelled: true))
        #expect(library.assets.count == 3)
        #expect(library.deleteRequests.count == 1)
    }

    @Test func userCancelIsCode3072InThePhotosErrorDomain() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3072)
        #expect(PhotoKitAssetDeletionService.failure(for: error) == .cancelledByUser)
    }

    @Test(arguments: [PhotoLibraryAuthorization.denied, .restricted, .notDetermined])
    func withoutReadWriteAccessEveryIDIsPermissionDenied(authorization: PhotoLibraryAuthorization) async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"])
        library.authorization = authorization
        let result = await makeService(library).delete(assetIDs: ["A", "B"])
        #expect(result == .permissionDenied(for: ["A", "B"]))
        #expect(library.deleteRequests.isEmpty)
    }

    @Test func limitedAccessCanDeleteAccessibleAssets() async {
        let library = FakePhotoLibraryPerformer(deletable: ["inLimitedSelection"])
        library.authorization = .limited
        let result = await makeService(library).delete(assetIDs: ["inLimitedSelection", "outsideSelection"])
        #expect(result == DeletionResult(deleted: ["inLimitedSelection"], failed: ["outsideSelection": .unavailable]))
    }

    @Test func accessRevokedDuringTheRequestIsPermissionDenied() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"])
        library.responses = [FakePhotoLibraryPerformer.photosError(.accessUserDenied)]
        let result = await makeService(library).delete(assetIDs: ["A", "B"])
        #expect(result == .permissionDenied(for: ["A", "B"]))
    }

    @Test func otherErrorsAreUnknownWithDomainAndCode() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A"])
        library.responses = [NSError(domain: "TestDomain", code: 7)]
        let result = await makeService(library).delete(assetIDs: ["A"])
        #expect(result == DeletionResult(failed: ["A": .unknown("TestDomain 7")]))
    }

    @Test func assetsStillPresentAfterSuccessAreNotDeleted() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"])
        library.removesAssetsOnSuccess = false
        let result = await makeService(library).delete(assetIDs: ["A", "B"])
        #expect(result == DeletionResult(failed: ["A": .notDeleted, "B": .notDeleted]))
    }

    @Test func assetsGoneBeforeTheChangeBlockAreUnavailableNotDeleted() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"])
        library.vanishBeforeRequest = ["B"]
        let result = await makeService(library).delete(assetIDs: ["A", "B"])
        #expect(result == DeletionResult(deleted: ["A"], failed: ["B": .unavailable]))
    }

    @Test func emptyRequestShowsNoSystemAlert() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A"])
        #expect(await makeService(library).delete(assetIDs: []) == DeletionResult())
        #expect(library.deleteRequests.isEmpty)
    }

    @Test func nothingDeletableShowsNoSystemAlert() async {
        let library = FakePhotoLibraryPerformer(notDeletable: ["shared"])
        let result = await makeService(library).delete(assetIDs: ["shared", "gone"])
        #expect(result == DeletionResult(failed: ["shared": .notDeletable, "gone": .unavailable]))
        #expect(library.deleteRequests.isEmpty)
    }

    @Test func repeatedIDsAreRequestedOnceInFirstSeenOrder() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B"])
        let result = await makeService(library).delete(assetIDs: ["B", "A", "B"])
        #expect(result == DeletionResult(deleted: ["A", "B"]))
        #expect(library.deleteRequests == [["B", "A"]])
    }
}

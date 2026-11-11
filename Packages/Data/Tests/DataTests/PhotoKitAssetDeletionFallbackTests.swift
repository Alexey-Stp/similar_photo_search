@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing

/// The chunked fallback (feature flag) and the mapping of PhotoKit errors.
struct PhotoKitAssetDeletionFallbackTests {
    private let failure = NSError(domain: "TestDomain", code: 1)

    @Test func withTheFlagOffAFailedRequestIsNotRetried() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C"])
        library.responses = [failure]
        let service = PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: nil)
        let result = await service.delete(assetIDs: ["A", "B", "C"])
        #expect(result.deleted.isEmpty)
        #expect(result.failed.count == 3)
        #expect(library.deleteRequests.count == 1)
    }

    @Test func theFlagSelectsTheFallbackChunkSize() {
        #expect(PhotoKitAssetDeletionService.chunkSize(chunksAfterFailure: false) == nil)
        #expect(PhotoKitAssetDeletionService.chunkSize(chunksAfterFailure: true) == 500)
    }

    @Test func withTheFlagOnAFailedRequestIsRetriedInChunks() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C", "D", "E"])
        library.responses = [failure]
        let service = PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: 2)
        let result = await service.delete(assetIDs: ["A", "B", "C", "D", "E"])
        #expect(result == DeletionResult(deleted: ["A", "B", "C", "D", "E"]))
        #expect(library.deleteRequests == [["A", "B", "C", "D", "E"], ["A", "B"], ["C", "D"], ["E"]])
    }

    @Test func aFailedChunkDoesNotStopTheOthers() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C"])
        library.responses = [failure, failure, nil]
        let service = PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: 2)
        let result = await service.delete(assetIDs: ["A", "B", "C"])
        let reason = DeletionError.unknown("TestDomain 1")
        #expect(result == DeletionResult(deleted: ["C"], failed: ["A": reason, "B": reason]))
    }

    @Test func cancellingAChunkStopsTheRestAndKeepsEarlierDeletions() async {
        let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C", "D", "E"])
        library.responses = [failure, nil, FakePhotoLibraryPerformer.photosError(.userCancelled)]
        let service = PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: 2)
        let result = await service.delete(assetIDs: ["A", "B", "C", "D", "E"])
        #expect(result == DeletionResult(deleted: ["A", "B"], cancelled: true))
        #expect(library.deleteRequests.count == 3)
    }

    @Test func cancelAndLostAccessAreNeverRetried() async {
        for error in [
            FakePhotoLibraryPerformer.photosError(.userCancelled),
            FakePhotoLibraryPerformer.photosError(.accessRestricted)
        ] {
            let library = FakePhotoLibraryPerformer(deletable: ["A", "B", "C"])
            library.responses = [error]
            let service = PhotoKitAssetDeletionService(library: library, chunkSizeAfterFailure: 1)
            _ = await service.delete(assetIDs: ["A", "B", "C"])
            #expect(library.deleteRequests.count == 1)
        }
    }

    @Test(arguments: [
        (PHPhotosError.Code.userCancelled, DeletionRequestFailure.cancelledByUser),
        (.accessUserDenied, .failed(.permissionDenied)),
        (.accessRestricted, .failed(.permissionDenied)),
        (.invalidResource, .failed(.unknown("\(PHPhotosErrorDomain) \(PHPhotosError.Code.invalidResource.rawValue)")))
    ])
    func mapsPhotoKitErrors(code: PHPhotosError.Code, expected: DeletionRequestFailure) {
        let error = NSError(domain: PHPhotosErrorDomain, code: code.rawValue)
        #expect(PhotoKitAssetDeletionService.failure(for: error) == expected)
    }

    @Test func userCancelledCodeOutsideThePhotosDomainIsUnknown() {
        let error = NSError(domain: "OtherDomain", code: PHPhotosError.Code.userCancelled.rawValue)
        #expect(PhotoKitAssetDeletionService.failure(for: error) == .failed(.unknown("OtherDomain 3072")))
    }
}

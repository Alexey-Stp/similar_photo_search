import Domain
import DomainTestSupport
import Foundation
import Testing

/// The deletion result's helpers and the mock service that later tickets test against.
struct DeletionResultTests {
    @Test func defaultResultIsEmptyAndNotCancelled() {
        let result = DeletionResult()
        #expect(result.deleted.isEmpty)
        #expect(result.failed.isEmpty)
        #expect(!result.cancelled)
        #expect(!result.isPermissionDenied)
    }

    @Test func permissionDeniedFailsEveryIDOnce() {
        let result = DeletionResult.permissionDenied(for: ["A", "B", "A"])
        #expect(result.failed == ["A": .permissionDenied, "B": .permissionDenied])
        #expect(result.deleted.isEmpty)
        #expect(!result.cancelled)
        #expect(result.isPermissionDenied)
    }

    @Test func otherFailuresAreNotPermissionDenied() {
        let result = DeletionResult(deleted: ["A"], failed: ["B": .notDeletable, "C": .unknown("X 1")])
        #expect(!result.isPermissionDenied)
    }

    @Test func mockDeletesEveryRequestedIDByDefault() async {
        let service = MockAssetDeletionService()
        let result = await service.delete(assetIDs: ["A", "B"])
        #expect(result == DeletionResult(deleted: ["A", "B"]))
        #expect(await service.deletionRequests == [["A", "B"]])
    }

    @Test func mockReturnsTheScriptedResult() async {
        let cancelled = DeletionResult(cancelled: true)
        let service = MockAssetDeletionService(result: cancelled)
        #expect(await service.delete(assetIDs: ["A"]) == cancelled)
        #expect(await service.delete(assetIDs: ["B"]) == cancelled)
        #expect(await service.deletionRequests == [["A"], ["B"]])
    }
}

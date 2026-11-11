import Domain
import Foundation
import os
import Photos

/// Deletes assets through one `PHPhotoLibrary.performChanges` call and maps every outcome to a `DeletionResult`.
///
/// Order of work: check `.readWrite` access, re-fetch the IDs (missing → `.unavailable`, not deletable →
/// `.notDeletable`), ask PhotoKit to delete the rest in one request (one system alert), then re-fetch the IDs PhotoKit
/// reported as deleted: only those that are really gone count as deleted, the rest fail with `.notDeleted`.
public actor PhotoKitAssetDeletionService: AssetDeletionService {
    /// Request size for the chunked fallback.
    public static let fallbackChunkSize = 500

    static let logger = Logger(subsystem: "com.similarphotos", category: "deletion")

    let library: any PhotoLibraryPerforming
    /// Chunk size of the fallback after a failed single request; `nil` when the feature flag is off.
    let chunkSizeAfterFailure: Int?

    /// Creates the service.
    ///
    /// - Parameter chunksAfterFailure: Feature flag, off by default. When on and the single request fails for a reason
    ///   other than a user cancel or missing access, the IDs are retried in requests of `fallbackChunkSize`, each with
    ///   its own system alert. Decide whether to turn it on after the 2,000-asset device spike.
    public init(chunksAfterFailure: Bool = false) {
        self.init(
            library: PhotoKitLibraryPerformer(),
            chunkSizeAfterFailure: Self.chunkSize(chunksAfterFailure: chunksAfterFailure)
        )
    }

    /// The fallback chunk size for the feature flag: `fallbackChunkSize` when on, `nil` when off.
    static func chunkSize(chunksAfterFailure: Bool) -> Int? {
        chunksAfterFailure ? fallbackChunkSize : nil
    }

    /// Creates the service over `library`; `chunkSizeAfterFailure` `nil` turns the chunked fallback off.
    init(library: any PhotoLibraryPerforming, chunkSizeAfterFailure: Int?) {
        precondition(chunkSizeAfterFailure.map { $0 > 0 } ?? true, "The fallback chunk size must be positive")
        self.library = library
        self.chunkSizeAfterFailure = chunkSizeAfterFailure
    }

    /// Deletes `assetIDs` and accounts for every requested ID in the result.
    ///
    /// - `deleted`: IDs this call submitted to PhotoKit and that a re-fetch afterwards no longer finds.
    /// - `failed`: `.permissionDenied` for every ID without read-write access; `.unavailable` for IDs that are gone,
    ///   not accessible, or vanished before the change block fetched them; `.notDeletable` for IDs PhotoKit won't
    ///   delete; `.notDeleted` for submitted IDs still present afterwards; `.unknown` or `.permissionDenied` for the
    ///   IDs of a request that failed.
    /// - `cancelled`: the user tapped "Don't Allow". With one request nothing was deleted. With the chunked fallback,
    ///   the cancel stops the remaining chunks; earlier chunks' deletions and failures stay in the result, and IDs of
    ///   the cancelled and later chunks are in neither `deleted` nor `failed`.
    public func delete(assetIDs: [String]) async -> DeletionResult {
        let requested = Self.unique(assetIDs)
        guard !requested.isEmpty else { return DeletionResult() }
        guard Self.allowsDeletion(library.readWriteAuthorization()) else {
            Self.logger.notice("Deletion refused: no read-write access to the photo library")
            return .permissionDenied(for: requested)
        }

        var result = DeletionResult()
        let eligible = prepareEligible(requested, failures: &result.failed)
        guard !eligible.isEmpty else { return result }

        let report = await performRequests(for: eligible)
        result.cancelled = report.cancelled
        result.failed.merge(report.failed) { _, new in new }
        confirmDeletion(of: report.succeeded, into: &result)

        let deletedCount = result.deleted.count
        let failedCount = result.failed.count
        Self.logger.info("Deletion: \(deletedCount) deleted, \(failedCount) failed, cancelled: \(result.cancelled)")
        return result
    }

    /// Re-fetches `requested` and returns the IDs that can be deleted, in request order; records the others.
    private func prepareEligible(_ requested: [String], failures: inout [String: DeletionError]) -> [String] {
        let deletability = library.deletability(of: requested)
        var eligible: [String] = []
        eligible.reserveCapacity(requested.count)
        for id in requested {
            switch deletability[id] {
            case .none: failures[id] = .unavailable
            case .some(false): failures[id] = .notDeletable
            case .some(true): eligible.append(id)
            }
        }
        return eligible
    }

    /// Re-fetches the IDs PhotoKit reported as deleted: gone ones are deleted, the rest fail with `.notDeleted`.
    private func confirmDeletion(of succeeded: [String], into result: inout DeletionResult) {
        guard !succeeded.isEmpty else { return }
        let stillPresent = library.deletability(of: succeeded)
        for id in succeeded {
            if stillPresent[id] == nil {
                result.deleted.insert(id)
            } else {
                result.failed[id] = .notDeleted
            }
        }
    }

    /// `ids` without repeats, in first-seen order.
    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Deleting needs full or Limited read-write access.
    static func allowsDeletion(_ authorization: PhotoLibraryAuthorization) -> Bool {
        switch authorization {
        case .authorized, .limited: true
        case .notDetermined, .denied, .restricted: false
        }
    }
}

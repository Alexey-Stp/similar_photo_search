#if DEBUG
import Domain
import Foundation

/// `ClusterRepository` for SwiftUI previews: returns fixed results and forgets writes.
struct PreviewClusterRepository: ClusterRepository {
    let results: [StoredSessionResult]

    /// Returns `results`.
    func storedResults() async -> [StoredSessionResult] { results }

    /// Does nothing; previews never persist.
    func apply(upserted: [StoredSessionResult], removedSessionIDs: Set<String>) async throws {}

    /// One stored session with the two groups of `SelectionStore.preview()`.
    static let sample = PreviewClusterRepository(results: [
        StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: PhotoSession.id(newestID: "A1", newestDate: Date(timeIntervalSince1970: 1_780_000_000)),
                content: SessionFingerprint.Content(memberCount: 5, digest: 1)
            ),
            clusters: [
                SimilarityCluster(assetIDs: ["A1", "A2", "A3"]),
                SimilarityCluster(assetIDs: ["B1", "B2"])
            ],
            resultsKey: "preview"
        )
    ])
}

/// `LibraryChangeObserving` for previews: the library never changes.
struct PreviewLibraryObserver: LibraryChangeObserving {
    /// A stream that never yields.
    func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

extension SelectionStore {
    /// A store without groups.
    static func empty() -> SelectionStore {
        SelectionStore(sizes: PreviewAssetSizeEstimator())
    }
}

extension ScanProgress {
    /// A finished scan of 10,000 photos with the given skips.
    static func previewDone(skipped: [SkipReason: Int] = [:]) -> ScanProgress {
        ScanProgress(processed: 10_000, total: 10_000, skipped: skipped, phase: .done)
    }
}

extension HomeViewModel {
    /// A Home whose scan shows `snapshot` once started.
    /// - Parameters:
    ///   - selection: The groups already found (none for idle and empty).
    ///   - stored: Whether a previous scan's results are stored: `launch()` then shows them and starts a silent
    ///     refresh (pass an empty `selection`, the stored groups fill it).
    static func preview(
        snapshot: ScanProgress = ScanProgress(processed: 3_120, total: 10_000, phase: .analyzing, eta: 140),
        selection: SelectionStore = .preview(),
        stored: Bool = false
    ) -> HomeViewModel {
        HomeViewModel(
            scan: .preview(snapshot: snapshot, selection: stored ? .empty() : selection),
            results: stored ? PreviewClusterRepository.sample : PreviewClusterRepository(results: []),
            libraryChanges: PreviewLibraryObserver()
        )
    }
}
#endif

#if DEBUG
import Domain
import SwiftUI

/// `AssetDeletionService` for SwiftUI previews: never touches PhotoKit; answers with `result` after a short wait.
struct PreviewDeletionService: AssetDeletionService {
    let result: @Sendable ([String]) -> DeletionResult

    /// Waits a second (the "system alert"), then returns the scripted result.
    func delete(assetIDs: [String]) async -> DeletionResult {
        try? await Task.sleep(for: .seconds(1))
        return result(assetIDs)
    }
}

/// `FeaturePrintCache` for SwiftUI previews: stores nothing.
struct PreviewFeaturePrintCache: FeaturePrintCache {
    /// No records.
    func validEntries(for assets: [PhotoAsset], revision: Int) async -> [String: AnalysisRecord] { [:] }
    /// Does nothing.
    func upsert(_ records: [AnalysisRecord]) async throws {}
    /// Does nothing.
    func purge(assetIDs: [String]) async throws {}
    /// No IDs.
    func cachedAssetIDs() async -> Set<String> { [] }
}

/// `PhotosAppOpening` for SwiftUI previews: offers the button, opens nothing.
@MainActor
final class PreviewPhotosAppOpener: PhotosAppOpening {
    /// Always `true`.
    var canOpenPhotos: Bool { true }
    /// Does nothing.
    func openPhotos() {}
}

extension DeletionViewModel {
    /// A flow for the preview store's selected photos (A2, A3) whose deletion returns `result`.
    static func preview(
        result: @escaping @Sendable ([String]) -> DeletionResult = { DeletionResult(deleted: Set($0)) }
    ) -> DeletionViewModel {
        let scan = ScanViewModel.preview()
        return DeletionViewModel(
            assetIDs: scan.selection.selectedAssetIDs,
            deletion: PreviewDeletionService(result: result),
            cache: PreviewFeaturePrintCache(),
            scan: scan,
            thumbnails: PreviewThumbnailLoader(),
            photosApp: PreviewPhotosAppOpener(),
            backgroundTasks: PreviewAppLifecycle()
        )
    }
}

#Preview("Review") {
    NavigationStack {
        DeletionFlowView(viewModel: .preview()) {}
    }
}

#Preview("Partial, dark, AX3") {
    let viewModel = DeletionViewModel.preview { ids in
        DeletionResult(deleted: Set(ids.dropLast()), failed: [ids[ids.count - 1]: .notDeletable])
    }
    return NavigationStack {
        DeletionFlowView(viewModel: viewModel) {}
    }
    .task { await viewModel.confirm() }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}

#Preview("Success") {
    let viewModel = DeletionViewModel.preview()
    return NavigationStack {
        DeletionFlowView(viewModel: viewModel) {}
    }
    .task { await viewModel.confirm() }
}
#endif

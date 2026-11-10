#if DEBUG
import Domain
import SwiftUI

/// `ThumbnailLoading` for SwiftUI previews: an SF Symbol on a colour picked from the photo ID, never PhotoKit.
struct PreviewThumbnailLoader: ThumbnailLoading {
    private static let symbols = ["mountain.2.fill", "sun.max.fill", "leaf.fill", "person.2.fill", "pawprint.fill"]
    private static let colors: [Color] = [.teal, .orange, .indigo, .pink, .green]

    /// One rendered symbol, then the stream ends.
    func thumbnail(for assetID: String, pixelSize: CGSize) -> AsyncStream<Thumbnail> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                if let image = Self.render(assetID: assetID, pixelSize: pixelSize) {
                    continuation.yield(image)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Does nothing.
    func prefetch(_ assetIDs: [String], pixelSize: CGSize) async {}

    /// Does nothing.
    func stopPrefetching(_ assetIDs: [String], pixelSize: CGSize) async {}

    /// Does nothing.
    func stopAllPrefetching() async {}

    /// Renders the symbol of `assetID` into a square bitmap.
    @MainActor
    private static func render(assetID: String, pixelSize: CGSize) -> Thumbnail? {
        let index = assetID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % symbols.count
        let side = max(1, min(pixelSize.width, pixelSize.height))
        let view = ZStack {
            colors[index].opacity(0.35)
            Image(systemName: symbols[index])
                .resizable()
                .scaledToFit()
                .padding(side / 4)
                .foregroundStyle(colors[index])
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        guard let cgImage = renderer.cgImage else { return nil }
        return Thumbnail(cgImage: cgImage, exifOrientation: .up)
    }
}

extension ClusterListViewModel {
    /// A list over `SelectionStore.preview()` with fake dates, sizes and thumbnails.
    static func preview(scan: ScanViewModel = .preview()) -> ClusterListViewModel {
        scan.showStoredResults(scan.selection.clusterIDs.compactMap { scan.selection.state(for: $0)?.suggestion })
        return ClusterListViewModel(
            scan: scan,
            library: PreviewPhotoLibraryRepository.sample,
            sizes: PreviewAssetSizeEstimator(),
            thumbnails: PreviewThumbnailLoader(),
            libraryChanges: PreviewLibraryObserver()
        )
    }
}
#endif

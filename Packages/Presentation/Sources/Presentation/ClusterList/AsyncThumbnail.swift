import SwiftUI

/// One photo's thumbnail, loaded while the view is on screen.
///
/// `.task(id:)` starts the request when the view appears and cancels it when the view leaves the screen (or the
/// photo changes), which cancels the PhotoKit request. With `.opportunistic` delivery the degraded image shows first
/// and is replaced by the final one. A photo that is missing or has no local data shows a placeholder.
struct AsyncThumbnail: View {
    let assetID: String
    let pixelSize: CGSize
    let isMissing: Bool
    let loader: any ThumbnailLoading

    @State private var thumbnail: Thumbnail?
    @State private var loadedID: String?

    /// The image once loaded, a placeholder before that or when the photo is missing.
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.fill.tertiary)
            if !isMissing, let thumbnail, loadedID == assetID {
                Image(decorative: thumbnail.cgImage, scale: 1, orientation: thumbnail.orientation)
                    .resizable()
                    .scaledToFill()
            } else if isMissing {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: LoadKey(assetID: assetID, width: pixelSize.width, height: pixelSize.height, isMissing: isMissing)) {
            await load()
        }
    }

    /// Restarts the load when the photo, the size or its availability changes.
    private struct LoadKey: Hashable {
        let assetID: String
        let width: CGFloat
        let height: CGFloat
        let isMissing: Bool
    }

    /// Shows each image the stream delivers; returns when it ends or is cancelled.
    private func load() async {
        if loadedID != assetID {
            thumbnail = nil
        }
        guard !isMissing else { return }
        for await image in loader.thumbnail(for: assetID, pixelSize: pixelSize) {
            thumbnail = image
            loadedID = assetID
        }
    }
}

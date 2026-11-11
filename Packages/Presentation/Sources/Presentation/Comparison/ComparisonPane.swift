import SwiftUI

/// One photo of the comparison at screen size: loaded while `isActive`, released when not (only the current photo
/// and its neighbours hold an image). An iCloud-only original shows its local preview with "Original in iCloud".
struct ComparisonPane: View {
    let assetID: String
    let isActive: Bool
    let isMissing: Bool
    let loader: any ScreenImageLoading
    let zoom: ZoomState
    let accessibilityLabel: String

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: ScreenImage?
    @State private var loadedKey: LoadKey?
    @State private var didFail = false

    /// The zoomable photo, a spinner while it loads, or a message when there is nothing to show.
    var body: some View {
        GeometryReader { proxy in
            let key = LoadKey(
                assetID: assetID,
                pixelSize: ComparisonLayout.pixelSize(points: proxy.size, scale: displayScale),
                isActive: isActive && !isMissing
            )
            ZStack {
                if let loaded, loadedKey?.assetID == assetID {
                    ZoomableImage(image: loaded.image, zoom: zoom, accessibilityLabel: accessibilityLabel)
                    if loaded.isOriginalInCloud {
                        ICloudOriginalLabel()
                    }
                } else if isMissing || didFail {
                    unavailable
                } else {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel(accessibilityLabel)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key) { await load(key) }
        }
    }

    /// Restarts the load when the photo, the size or whether it should be held changes.
    private struct LoadKey: Hashable {
        let assetID: String
        let pixelSize: CGSize
        let isActive: Bool

        /// Hashes the fields one by one (`CGSize` is not `Hashable`).
        func hash(into hasher: inout Hasher) {
            hasher.combine(assetID)
            hasher.combine(pixelSize.width)
            hasher.combine(pixelSize.height)
            hasher.combine(isActive)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: isMissing ? "questionmark.square.dashed" : "exclamationmark.triangle")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(isMissing ? LocalizedStringKey("compare.photo.missing") : "compare.photo.failed", bundle: .module)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
        .accessibilityElement(children: .combine)
    }

    /// Loads the image for `key`, or releases it when the pane is not active.
    private func load(_ key: LoadKey) async {
        guard key.isActive else {
            loaded = nil
            loadedKey = nil
            didFail = false
            return
        }
        if loadedKey == key, loaded != nil { return }
        if loadedKey?.assetID != key.assetID {
            loaded = nil
        }
        didFail = false
        let image = await loader.screenImage(for: key.assetID, pixelSize: key.pixelSize)
        guard !Task.isCancelled else { return }
        loaded = image
        loadedKey = image == nil ? nil : key
        didFail = image == nil
    }
}

/// "Original in iCloud" on the local preview of an iCloud-only photo.
private struct ICloudOriginalLabel: View {
    /// A capsule at the bottom of the photo; touches pass through.
    var body: some View {
        VStack {
            Spacer()
            Label {
                Text("compare.iCloudOriginal", bundle: .module)
            } icon: {
                Image(systemName: "icloud")
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
        }
        .allowsHitTesting(false)
    }
}

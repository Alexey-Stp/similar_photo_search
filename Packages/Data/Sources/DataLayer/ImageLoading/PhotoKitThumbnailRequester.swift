import CoreGraphics
import Foundation
import Photos

/// Starts and stops a thumbnail cache: `PHCachingImageManager` in the app, a fake in tests.
public protocol ThumbnailCaching: Sendable {
    /// Starts preparing thumbnails of these photos at `targetSize` pixels. Unknown IDs are ignored.
    func startCaching(assetIDs: [String], targetSize: CGSize)
    /// Stops preparing (and releases) thumbnails of these photos at `targetSize` pixels.
    func stopCaching(assetIDs: [String], targetSize: CGSize)
    /// Releases every cached thumbnail.
    func stopCachingAll()
}

/// Thumbnails for the group list over `PHCachingImageManager`: aspect-fill, `.opportunistic` (a fast degraded image,
/// then the final one), local only. iCloud-only photos show the local preview PhotoKit has, or a placeholder; they
/// are never downloaded.
///
/// Requests and caching use the same options, size and content mode, so prefetched thumbnails are actually reused.
public final class PhotoKitThumbnailRequester: ImageRequesting, ThumbnailCaching, @unchecked Sendable {
    /// Thumbnails fill their square cell.
    public static let contentMode: PHImageContentMode = .aspectFill

    // `PHCachingImageManager` is thread-safe; it is only stored and called.
    private let manager: PHCachingImageManager

    /// Creates the requester over a new `PHCachingImageManager`.
    public init() {
        manager = PHCachingImageManager()
        // Only the fast versions are cached; scrolling stays smooth and the cache small.
        manager.allowsCachingHighQualityImages = false
    }

    /// The options for every thumbnail request and cache call.
    public static func makeOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.version = .current
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        return options
    }

    /// Requests a thumbnail, or returns `nil` if no photo has `assetID`. The handler is called once or twice.
    public func requestImage(
        assetID: String,
        targetSize: CGSize,
        resultHandler: @escaping @Sendable (ImageRequestResult) -> Void
    ) -> ImageRequestID? {
        autoreleasepool { () -> ImageRequestID? in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                return nil
            }
            return manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: Self.contentMode,
                options: Self.makeOptions()
            ) { image, info in
                let result = autoreleasepool {
                    PhotoKitImageRequester.result(image: image, info: info)
                }
                resultHandler(result)
            }
        }
    }

    /// Cancels the PhotoKit request.
    public func cancelRequest(_ requestID: ImageRequestID) {
        manager.cancelImageRequest(requestID)
    }

    /// Starts caching the photos that still exist.
    public func startCaching(assetIDs: [String], targetSize: CGSize) {
        guard !assetIDs.isEmpty else { return }
        autoreleasepool {
            let assets = Self.fetch(assetIDs)
            guard !assets.isEmpty else { return }
            manager.startCachingImages(
                for: assets,
                targetSize: targetSize,
                contentMode: Self.contentMode,
                options: Self.makeOptions()
            )
        }
    }

    /// Stops caching the photos.
    public func stopCaching(assetIDs: [String], targetSize: CGSize) {
        guard !assetIDs.isEmpty else { return }
        autoreleasepool {
            let assets = Self.fetch(assetIDs)
            guard !assets.isEmpty else { return }
            manager.stopCachingImages(
                for: assets,
                targetSize: targetSize,
                contentMode: Self.contentMode,
                options: Self.makeOptions()
            )
        }
    }

    /// Releases the whole cache.
    public func stopCachingAll() {
        manager.stopCachingImagesForAllAssets()
    }

    /// The assets with these identifiers that still exist, in PhotoKit order.
    private static func fetch(_ assetIDs: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}

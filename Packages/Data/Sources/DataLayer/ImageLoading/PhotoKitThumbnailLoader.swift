import CoreGraphics
import Foundation

/// Thumbnails for the group list: one cancellable stream per cell, and a **bounded** prefetch window.
///
/// - `thumbnail(for:size:)` yields what the `.opportunistic` request delivers (degraded, then final) and finishes on
///   the final callback, an error, a cancellation, or when the photo doesn't exist. Ending the stream early (the
///   cell left the screen) cancels the PhotoKit request.
/// - `prefetch` keeps at most `maxCachedAssets` photos per size in the cache, least recently prefetched out first,
///   so `startCachingImages` can never grow without limit however far the user scrolls.
public actor PhotoKitThumbnailLoader {
    /// Default bound of the prefetch cache, in photos.
    public static let defaultMaxCachedAssets = 300

    private nonisolated let requester: any ImageRequesting
    private let cache: any ThumbnailCaching
    private let maxCachedAssets: Int
    /// Cached photos per size, least recently prefetched first.
    private var cached: [SizeKey: [String]] = [:]

    /// Creates the loader over `PHCachingImageManager`.
    public init() {
        let requester = PhotoKitThumbnailRequester()
        self.init(requester: requester, cache: requester)
    }

    /// Creates the loader over any request and cache API, for example fakes in tests.
    public init(
        requester: any ImageRequesting,
        cache: any ThumbnailCaching,
        maxCachedAssets: Int = PhotoKitThumbnailLoader.defaultMaxCachedAssets
    ) {
        self.requester = requester
        self.cache = cache
        self.maxCachedAssets = max(1, maxCachedAssets)
    }

    /// The thumbnail of one photo at `size` pixels: zero, one or two images.
    public nonisolated func thumbnail(for assetID: String, size: CGSize) -> AsyncStream<LoadedImage> {
        let requester = requester
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let pending = CancellableImageRequest(requester: requester)
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    pending.cancel()
                }
            }
            let requestID = requester.requestImage(assetID: assetID, targetSize: size) { result in
                if let image = result.image, !result.isCancelled {
                    continuation.yield(image)
                }
                if !result.isDegraded || result.isCancelled || result.hasError {
                    continuation.finish()
                }
            }
            if let requestID {
                pending.attach(requestID)
            } else {
                continuation.finish()
            }
        }
    }

    /// Starts caching these photos at `size`; the oldest cached ones are released beyond `maxCachedAssets`.
    public func prefetch(_ assetIDs: [String], size: CGSize) {
        let key = SizeKey(size)
        var order = cached[key] ?? []
        let incoming = Set(assetIDs)
        let alreadyCached = Set(order)
        order.removeAll { incoming.contains($0) }
        var seen = Set<String>()
        let unique = assetIDs.filter { seen.insert($0).inserted }
        order.append(contentsOf: unique)
        let start = unique.filter { !alreadyCached.contains($0) }
        if !start.isEmpty {
            cache.startCaching(assetIDs: start, targetSize: size)
        }
        if order.count > maxCachedAssets {
            let evicted = Array(order.prefix(order.count - maxCachedAssets))
            order.removeFirst(evicted.count)
            cache.stopCaching(assetIDs: evicted, targetSize: size)
        }
        cached[key] = order
    }

    /// Stops caching these photos at `size`. Photos that are not cached are ignored.
    public func stopPrefetching(_ assetIDs: [String], size: CGSize) {
        let key = SizeKey(size)
        guard var order = cached[key] else { return }
        let removed = Set(assetIDs).intersection(order)
        guard !removed.isEmpty else { return }
        order.removeAll { removed.contains($0) }
        cached[key] = order.isEmpty ? nil : order
        cache.stopCaching(assetIDs: assetIDs.filter { removed.contains($0) }, targetSize: size)
    }

    /// Releases every cached thumbnail.
    public func stopAllPrefetching() {
        cached = [:]
        cache.stopCachingAll()
    }

    /// The photos cached at `size`, least recently prefetched first. For tests.
    public func cachedAssetIDs(size: CGSize) -> [String] {
        cached[SizeKey(size)] ?? []
    }

    /// `CGSize` is not `Hashable`; sizes are whole pixels anyway.
    private struct SizeKey: Hashable {
        let width: Int
        let height: Int

        /// The key of a size, rounded to whole pixels.
        init(_ size: CGSize) {
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
    }
}

/// The ID of one image request, so a cancellation can reach it even if it happens before the ID is known. Shared
/// with `PhotoKitScreenImageLoader`.
final class CancellableImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let requester: any ImageRequesting
    private var requestID: ImageRequestID?
    private var isCancelled = false

    /// Creates the holder for one request of `requester`.
    init(requester: any ImageRequesting) {
        self.requester = requester
    }

    /// Stores the request ID; cancels the request at once if the stream was already cancelled.
    func attach(_ requestID: ImageRequestID) {
        lock.lock()
        let cancelNow = isCancelled
        if !cancelNow {
            self.requestID = requestID
        }
        lock.unlock()
        if cancelNow {
            requester.cancelRequest(requestID)
        }
    }

    /// Cancels the request, now or as soon as its ID is known.
    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        self.requestID = nil
        lock.unlock()
        if let requestID {
            requester.cancelRequest(requestID)
        }
    }
}

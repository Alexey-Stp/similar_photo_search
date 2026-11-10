import Domain
import Foundation
import Photos

/// Estimates photo sizes from the undocumented `fileSize` key of `PHAssetResource` (KVC).
///
/// The size of a photo is the sum of its resources (original, edited full-size image, adjustment data, Live Photo
/// video), so it approximates what deleting the photo frees. It is an estimate: the key is not public API. If the key
/// disappears in an iOS update, every size becomes unavailable and the UI shows "size unavailable"; it never crashes,
/// because the key is only read when the resource responds to it.
///
/// Reads metadata only: no image data and no network. Runs on its own actor, off the main thread, in batches.
public actor PhotoKitAssetSizeEstimator: AssetSizeEstimator {
    /// The undocumented KVC key.
    static let fileSizeKey = "fileSize"

    private let batchSize: Int

    /// Creates the estimator.
    /// - Parameter batchSize: How many photos are fetched per `PHAsset.fetchAssets` call.
    public init(batchSize: Int = 200) {
        self.batchSize = max(1, batchSize)
    }

    /// Sizes in bytes of the photos whose size is known; missing photos and unknown sizes are left out.
    public func estimatedSizes(of assetIDs: [String]) async -> [String: Int64] {
        var seen = Set<String>()
        let ids = assetIDs.filter { seen.insert($0).inserted }
        var result: [String: Int64] = [:]
        var start = 0
        while start < ids.count, !Task.isCancelled {
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            autoreleasepool {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: batch, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    let resources = PHAssetResource.assetResources(for: asset)
                    if let size = Self.totalSize(of: resources.map(Self.fileSize)) {
                        result[asset.localIdentifier] = size
                    }
                }
            }
            start += batchSize
        }
        return result
    }

    /// The resource's `fileSize`, or `nil` if the key is unavailable.
    static func fileSize(of resource: PHAssetResource) -> Any? {
        guard resource.responds(to: NSSelectorFromString(fileSizeKey)) else { return nil }
        return resource.value(forKey: fileSizeKey)
    }

    /// The sum of the sizes that are known (non-negative integers), or `nil` if none is.
    static func totalSize(of values: [Any?]) -> Int64? {
        var total: Int64 = 0
        var found = false
        for value in values {
            let size: Int64?
            switch value {
            case let number as NSNumber: size = number.int64Value
            case let number as Int64: size = number
            case let number as Int: size = Int64(number)
            default: size = nil
            }
            guard let size, size >= 0 else { continue }
            total += size
            found = true
        }
        return found ? total : nil
    }
}

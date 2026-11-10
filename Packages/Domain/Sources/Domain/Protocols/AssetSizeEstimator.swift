import Foundation

/// Estimates how much storage photos take, to show "38 photos, about 214 MB will be deleted" before a deletion.
///
/// The sizes are estimates: the implementation may rely on undocumented metadata, so a size can be missing.
/// It reads metadata only: no image data, no network.
public protocol AssetSizeEstimator: Sendable {
    /// The size in bytes of each photo whose size is known, keyed by asset ID. Photos that don't exist or whose size
    /// is unavailable are missing from the result. Stops early and returns what it has if the task is cancelled.
    func estimatedSizes(of assetIDs: [String]) async -> [String: Int64]
}

import Domain
import Foundation

/// `AssetSizeEstimator` that returns preset sizes and records the IDs it was asked about.
///
/// IDs without a preset size are missing from the result ("size unavailable").
public final class MockAssetSizeEstimator: AssetSizeEstimator, @unchecked Sendable {
    private let sizes: [String: Int64]
    private let lock = NSLock()
    private var requests: [[String]] = []

    /// Creates the mock with sizes in bytes by asset ID.
    public init(sizes: [String: Int64] = [:]) {
        self.sizes = sizes
    }

    /// The ID lists passed to `estimatedSizes(of:)`, in call order.
    public var calls: [[String]] {
        lock.withLock { requests }
    }

    /// Returns the preset sizes of the known IDs.
    public func estimatedSizes(of assetIDs: [String]) async -> [String: Int64] {
        lock.withLock { requests.append(assetIDs) }
        var result: [String: Int64] = [:]
        for id in assetIDs {
            if let size = sizes[id] {
                result[id] = size
            }
        }
        return result
    }
}

import Domain
import Foundation

/// `FeaturePrintService` that returns preset prints; unknown IDs behave like skipped iCloud-only photos.
public actor MockFeaturePrintService: FeaturePrintService {
    /// Prints returned by asset ID.
    public let featurePrints: [String: FeaturePrint]
    /// Asset IDs requested so far, in order.
    public private(set) var requestedAssetIDs: [String] = []

    /// Creates the mock.
    public init(featurePrints: [String: FeaturePrint] = [:]) {
        self.featurePrints = featurePrints
    }

    public func featurePrint(for assetID: String) -> FeaturePrint? {
        requestedAssetIDs.append(assetID)
        return featurePrints[assetID]
    }
}

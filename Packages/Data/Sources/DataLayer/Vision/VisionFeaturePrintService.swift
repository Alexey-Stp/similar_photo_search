import Domain
import Foundation

/// Vision `VNGenerateImageFeaturePrintRequest`-based service. Placeholder until the feature-print ticket.
public actor VisionFeaturePrintService: FeaturePrintService {
    /// Creates the service.
    public init() {}

    public func featurePrint(for assetID: String) async throws -> FeaturePrint? {
        fatalError("Not implemented")
    }
}

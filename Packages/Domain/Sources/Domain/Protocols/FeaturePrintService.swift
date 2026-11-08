import Foundation

/// Computes Vision feature prints for photos.
public protocol FeaturePrintService: Sendable {
    /// Computes the feature print of a photo.
    ///
    /// - Parameter assetID: The PhotoKit `localIdentifier` of the photo.
    /// - Returns: The feature print, or `nil` if the original is only in iCloud and was skipped.
    func featurePrint(for assetID: String) async throws -> FeaturePrint?
}

import Foundation

/// Computes Vision feature prints for photos. The implementation loads the image itself; Domain never sees pixels.
public protocol FeaturePrintService: Sendable {
    /// The Vision revision that new prints are computed with.
    ///
    /// A cached print of another revision is stale: vectors of different revisions must never be compared.
    var revision: Int { get }

    /// Computes the feature print of a photo.
    ///
    /// A photo whose image can't be loaded is `.skipped`, and a photo that Vision can't analyse is `.failed`; neither
    /// throws, so a scan goes on with the next photo.
    ///
    /// - Parameter asset: The photo. Its `modificationDate` is stored in the print as part of the cache key.
    /// - Throws: `CancellationError` if the calling task was cancelled. Nothing else.
    func featurePrint(for asset: PhotoAsset) async throws -> FeaturePrintOutcome
}

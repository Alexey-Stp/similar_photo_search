import Foundation

/// Persistent cache of feature prints.
///
/// An entry is valid only if asset ID, revision and modification date all match.
public protocol FeaturePrintCache: Sendable {
    /// Returns the cached print if one exists for exactly this asset, revision and modification date.
    func cachedFeaturePrint(for assetID: String, revision: Int, modificationDate: Date?) async -> FeaturePrint?

    /// Stores a print, replacing any previous entry for the same asset.
    func store(_ featurePrint: FeaturePrint) async throws
}

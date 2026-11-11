import Foundation

/// Tells which photos have edits, for the "Edited" badge of the comparison screen (SPS-22).
///
/// Reads only metadata: it never loads or downloads image data, so it also works for iCloud-only photos.
public protocol PhotoEditStatusProviding: Sendable {
    /// The photos among `assetIDs` that have edits. Photos that no longer exist are left out.
    func editedAssetIDs(among assetIDs: [String]) async -> Set<String>
}

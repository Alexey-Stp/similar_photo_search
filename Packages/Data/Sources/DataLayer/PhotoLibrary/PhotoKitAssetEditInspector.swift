import Foundation
import Photos

/// Tells whether a photo has edits. Synchronous: call it off the main thread.
public protocol AssetEditInspecting: Sendable {
    /// Whether the photo has edits, or `nil` if no photo has `assetID`.
    func isEdited(assetID: String) -> Bool?
}

/// Reads edits from the photo's resources: an edited photo has adjustment data (or a rendered full-size photo).
///
/// Only lists resource metadata; never loads or downloads any resource data, so it works for iCloud-only photos
/// without network access. `PHAsset` stays inside this call.
public struct PhotoKitAssetEditInspector: AssetEditInspecting {
    /// Creates the inspector.
    public init() {}

    /// Whether the photo has edits, or `nil` if it no longer exists.
    public func isEdited(assetID: String) -> Bool? {
        autoreleasepool {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                return nil
            }
            let types = PHAssetResource.assetResources(for: asset).map(\.type)
            return Self.isEdited(resourceTypes: types)
        }
    }

    /// Whether resources of these types mean the photo was edited.
    static func isEdited(resourceTypes: [PHAssetResourceType]) -> Bool {
        resourceTypes.contains { $0 == .adjustmentData || $0 == .fullSizePhoto }
    }
}

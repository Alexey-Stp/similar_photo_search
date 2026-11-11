import Domain
import Foundation

/// `PhotoEditStatusProviding` over `AssetEditInspecting`: lists resource metadata only, never image data, so it works
/// for iCloud-only photos without the network. An `actor`, so the synchronous PhotoKit calls stay off the main actor.
public actor PhotoKitEditStatusProvider: PhotoEditStatusProviding {
    private let inspector: any AssetEditInspecting

    /// Creates the provider.
    /// - Parameter inspector: Reads one photo's resources; `PhotoKitAssetEditInspector` in the app.
    public init(inspector: any AssetEditInspecting) {
        self.inspector = inspector
    }

    /// The photos among `assetIDs` that have edits; missing photos are left out. Stops early when cancelled.
    public func editedAssetIDs(among assetIDs: [String]) async -> Set<String> {
        var edited = Set<String>()
        for assetID in assetIDs {
            guard !Task.isCancelled else { break }
            if inspector.isEdited(assetID: assetID) == true {
                edited.insert(assetID)
            }
        }
        return edited
    }
}

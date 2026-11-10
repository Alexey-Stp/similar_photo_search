import Domain
import Foundation

/// `PhotoEditStatusProviding` fake: a fixed set of edited photos; records every request.
public actor MockPhotoEditStatusProvider: PhotoEditStatusProviding {
    private let edited: Set<String>
    /// The IDs of every request, in order.
    public private(set) var requests: [[String]] = []

    /// Creates the fake.
    /// - Parameter edited: The photos that have edits.
    public init(edited: Set<String> = []) {
        self.edited = edited
    }

    /// The requested IDs that are in `edited`.
    public func editedAssetIDs(among assetIDs: [String]) async -> Set<String> {
        requests.append(assetIDs)
        return edited.intersection(assetIDs)
    }
}

import Domain
import Foundation

/// In-memory `FeaturePrintCache` that applies the real validity rule (ID, revision and modification date).
public actor MockFeaturePrintCache: FeaturePrintCache {
    /// Stored prints by asset ID.
    public private(set) var entries: [String: FeaturePrint]

    /// Creates the mock.
    public init(entries: [FeaturePrint] = []) {
        self.entries = Dictionary(entries.map { ($0.assetID, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func cachedFeaturePrint(for assetID: String, revision: Int, modificationDate: Date?) -> FeaturePrint? {
        guard let entry = entries[assetID],
              entry.revision == revision,
              entry.assetModificationDate == modificationDate else {
            return nil
        }
        return entry
    }

    public func store(_ featurePrint: FeaturePrint) {
        entries[featurePrint.assetID] = featurePrint
    }
}

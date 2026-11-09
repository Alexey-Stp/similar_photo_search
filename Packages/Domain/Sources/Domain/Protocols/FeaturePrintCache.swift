import Foundation

/// Persistent cache of analysis results (feature prints, failures, quality scores), so later scans skip Vision for
/// unchanged photos.
///
/// An entry is valid only if asset ID, revision and modification date all match
/// (`AnalysisRecord.isValid(for:revision:)`).
/// Read one shooting session at a time: a Revision 2 vector is about 3 KB, so the whole table of a large library is
/// hundreds of megabytes.
public protocol FeaturePrintCache: Sendable {
    /// Returns the valid records for `assets` under `revision`, keyed by asset ID.
    ///
    /// Photos without a valid record (none stored, other revision, modified since) are missing from the result and
    /// must be analysed again. Never throws: if the store can't be read, every photo is a miss.
    func validEntries(for assets: [PhotoAsset], revision: Int) async -> [String: AnalysisRecord]

    /// Stores records, replacing any previous record of the same asset. If `records` names an asset twice, the
    /// last one wins. Implementations write in batches, so pass a whole session (or more) at once.
    func upsert(_ records: [AnalysisRecord]) async throws

    /// Removes the records of deleted photos. Unknown IDs are ignored.
    func purge(assetIDs: [String]) async throws

    /// The asset IDs of every stored record, of any revision, for the full-diff fallback of change tracking.
    ///
    /// Reads only the IDs, never the vectors. Never throws: if the store can't be read, the result is empty (so
    /// nothing is evicted).
    func cachedAssetIDs() async -> Set<String>
}

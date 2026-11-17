import Foundation

extension SelectionStore {
    /// Estimates the sizes of photos that may not be selected (the "Delete Now" review), without selecting them or
    /// touching the running estimate of the selection. `summary(of:)` includes them once they arrive.
    public func estimateSizes(of assetIDs: [String]) {
        let missing = assetIDs.filter { knownSizes[$0] == nil && !unavailableSizes.contains($0) }
        guard !missing.isEmpty else { return }
        let sizes = sizes
        Task { [weak self] in
            let found = await sizes.estimatedSizes(of: missing)
            self?.recordExtraSizes(found, requested: missing)
        }
    }

    /// Stores the sizes found, marks the rest unavailable, signals the change, and refreshes the selection's
    /// summary: a photo selected meanwhile may have been reported unavailable by the regular estimate.
    private func recordExtraSizes(_ found: [String: Int64], requested: [String]) {
        for id in requested {
            if let size = found[id], size >= 0 {
                knownSizes[id] = size
                unavailableSizes.remove(id)
            } else if knownSizes[id] == nil {
                unavailableSizes.insert(id)
            }
        }
        extraSizesRevision += 1
        updateSummary(for: selectedAssetIDs)
    }
}

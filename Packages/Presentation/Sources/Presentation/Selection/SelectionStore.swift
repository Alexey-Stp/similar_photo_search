import Domain
import Foundation
import Observation

/// The user's keep / delete choice for every cluster of the current session, and its total before deletion.
///
/// - Every cluster starts from its Smart Selection suggestion (`SmartSelectionUseCase`); the user can override any
///   photo with `toggle(_:in:)`, and the Best photo with `markAsBest(_:in:)` or `keepOnly(_:in:excluding:)`.
/// - Overrides last for the app session. When a cluster with the same ID and the **same members** arrives again (a
///   re-cluster, a rescan), the user's choice is restored; when its members changed, the new suggestion applies.
/// - Invariant: a cluster always keeps at least one photo. Selecting the last kept photo returns
///   `.needsConfirmation` and changes nothing; only `confirmDeleteAll(_:)` selects every member.
///
/// Observation is scoped: a cell reads its cluster's `ClusterSelectionState` (`state(for:)`), so a toggle re-renders
/// only that cluster; `selectedCount` and `summary` are for the toolbar.
@Observable
@MainActor
public final class SelectionStore {
    /// What `toggle(_:in:)` did.
    public enum ToggleResult: Sendable, Equatable {
        /// The photo is now selected for deletion.
        case selected
        /// The photo is now kept.
        case deselected
        /// Selecting it would leave the cluster with no kept photo. Nothing changed; ask the user, then call
        /// `confirmDeleteAll(_:)`.
        case needsConfirmation
        /// The cluster is unknown or the photo is not one of its members. Nothing changed.
        case notFound
    }

    /// IDs of the clusters, in the order they first arrived (the UI only appends rows).
    public internal(set) var clusterIDs: [String] = []
    /// Number of photos selected for deletion across all clusters.
    public private(set) var selectedCount = 0
    /// The count and the estimated size of the photos selected for deletion, shown before any deletion.
    public private(set) var summary = DeletionSummary.empty

    var states: [String: ClusterSelectionState] = [:]
    var clusterIDByAsset: [String: String] = [:]

    /// The user's choices by cluster ID, kept even while the cluster is gone (session-long).
    @ObservationIgnored var overrides: [String: Override] = [:]
    @ObservationIgnored private var knownSizes: [String: Int64] = [:]
    @ObservationIgnored private var unavailableSizes: Set<String> = []
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    private let sizes: any AssetSizeEstimator

    /// Creates an empty store.
    /// - Parameter sizes: Estimates file sizes for the summary; called off the main actor, only for selected photos
    ///   whose size is not known yet.
    public init(sizes: any AssetSizeEstimator) {
        self.sizes = sizes
    }

    // MARK: - Reading

    /// The live choice for one cluster, or `nil` if it is unknown.
    public func state(for clusterID: String) -> ClusterSelectionState? {
        states[clusterID]
    }

    /// Whether the photo is a cluster member that will be kept. `false` for photos in no cluster.
    public func isKept(_ assetID: String) -> Bool {
        guard let clusterID = clusterIDByAsset[assetID] else { return false }
        return states[clusterID]?.isKept(assetID) ?? false
    }

    /// Whether the photo is selected for deletion.
    public func isSelected(_ assetID: String) -> Bool {
        guard let clusterID = clusterIDByAsset[assetID] else { return false }
        return states[clusterID]?.isSelected(assetID) ?? false
    }

    /// The photos selected for deletion: clusters in arrival order, members in library order.
    public var selectedAssetIDs: [String] {
        var result: [String] = []
        for clusterID in clusterIDs {
            guard let state = states[clusterID] else { continue }
            var seen = Set<String>()
            for id in state.memberIDs where state.selectedIDs.contains(id) && seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    /// The summary of the selected photos except `excluded` (for example photos deleted outside the app, which
    /// can't be deleted again). Equals `summary` when nothing is excluded.
    public func summary(excluding excluded: Set<String>) -> DeletionSummary {
        guard !excluded.isEmpty else { return summary }
        return makeSummary(for: selectedAssetIDs.filter { !excluded.contains($0) })
    }

    // MARK: - Clusters

    /// Adds clusters, or replaces those with the same ID. A cluster whose members equal those of a previous choice
    /// gets that choice back; otherwise it starts from its suggestion.
    public func upsert(_ selections: [ClusterSelection]) {
        guard !selections.isEmpty else { return }
        for selection in selections {
            if let previous = states[selection.id] {
                unindex(previous)
            } else {
                clusterIDs.append(selection.id)
            }
            let members = Set(selection.cluster.assetIDs)
            var selected = selection.suggestedForDeletion.intersection(members)
            var confirmed = false
            var keeper: String?
            if let override = overrides[selection.id] {
                if override.members == members {
                    selected = override.selectedIDs
                    confirmed = override.isDeleteAllConfirmed
                    keeper = override.keeperID
                } else {
                    overrides[selection.id] = nil
                }
            }
            if selected == members, !confirmed, members.count > 0 {
                // A suggestion never selects every member; this guards against a malformed one.
                selected = []
            }
            let state = ClusterSelectionState(
                suggestion: selection,
                selectedIDs: selected,
                isDeleteAllConfirmed: confirmed,
                chosenKeeperID: keeper
            )
            states[selection.id] = state
            for id in selection.cluster.assetIDs {
                clusterIDByAsset[id] = selection.id
            }
        }
        refreshTotals()
    }

    /// Removes clusters, for example when a rescan replaces them. The user's choices are remembered for the session.
    public func remove(clusterIDs removed: some Sequence<String>) {
        let removedIDs = Set(removed)
        guard !removedIDs.isEmpty else { return }
        for id in removedIDs {
            guard let state = states.removeValue(forKey: id) else { continue }
            unindex(state)
        }
        clusterIDs.removeAll { removedIDs.contains($0) }
        refreshTotals()
    }

    // MARK: - Choosing

    /// Selects a kept photo for deletion, or keeps a selected one.
    ///
    /// Selecting the last kept photo of a cluster returns `.needsConfirmation` and changes nothing.
    @discardableResult
    public func toggle(_ assetID: String, in clusterID: String) -> ToggleResult {
        guard let state = states[clusterID], state.memberIDs.contains(assetID) else { return .notFound }
        let result: ToggleResult
        if state.selectedIDs.contains(assetID) {
            state.selectedIDs.remove(assetID)
            state.isDeleteAllConfirmed = false
            result = .deselected
        } else {
            let keptAfter = Set(state.memberIDs).subtracting(state.selectedIDs).subtracting([assetID])
            guard !keptAfter.isEmpty else { return .needsConfirmation }
            state.selectedIDs.insert(assetID)
            result = .selected
        }
        recordOverride(of: state)
        refreshTotals()
        return result
    }

    /// Selects every member of the cluster for deletion, after the user explicitly confirmed it.
    public func confirmDeleteAll(_ clusterID: String) {
        guard let state = states[clusterID] else { return }
        state.selectedIDs = Set(state.memberIDs)
        state.isDeleteAllConfirmed = true
        recordOverride(of: state)
        refreshTotals()
    }

    /// Resets every cluster to its Smart Selection suggestion (keeper included) and forgets all overrides.
    public func selectSmartAll() {
        overrides.removeAll()
        for state in states.values {
            let suggested = state.suggestion.suggestedForDeletion.intersection(state.memberIDs)
            if state.selectedIDs != suggested {
                state.selectedIDs = suggested
            }
            if state.isDeleteAllConfirmed {
                state.isDeleteAllConfirmed = false
            }
            if state.chosenKeeperID != nil {
                state.chosenKeeperID = nil
            }
        }
        refreshTotals()
    }

    /// Keeps every photo. Remembered as an override, so a re-cluster with the same members does not reselect them.
    public func deselectAll() {
        for state in states.values {
            if !state.selectedIDs.isEmpty {
                state.selectedIDs = []
            }
            if state.isDeleteAllConfirmed {
                state.isDeleteAllConfirmed = false
            }
            recordOverride(of: state)
        }
        refreshTotals()
    }

    /// Waits until the size estimate in progress, if any, has finished. For tests.
    public func waitForSizeEstimate() async {
        await sizeTask?.value
    }

    // MARK: - Private

    /// A user's choice for one cluster, valid only for the same members.
    struct Override {
        let members: Set<String>
        let selectedIDs: Set<String>
        let isDeleteAllConfirmed: Bool
        let keeperID: String?
    }

    func unindex(_ state: ClusterSelectionState) {
        for id in state.memberIDs where clusterIDByAsset[id] == state.id {
            clusterIDByAsset[id] = nil
        }
    }

    /// Remembers the cluster's choice (selection, delete-all, chosen Best) while it differs from the suggestion.
    func recordOverride(of state: ClusterSelectionState) {
        if state.isOverridden {
            overrides[state.id] = Override(
                members: Set(state.memberIDs),
                selectedIDs: state.selectedIDs,
                isDeleteAllConfirmed: state.isDeleteAllConfirmed,
                keeperID: state.chosenKeeperID
            )
        } else {
            overrides[state.id] = nil
        }
    }

    /// Updates the count and the summary, and starts estimating sizes that are not known yet.
    func refreshTotals() {
        let selected = selectedAssetIDs
        if selectedCount != selected.count {
            selectedCount = selected.count
        }
        updateSummary(for: selected)

        let missing = selected.filter { knownSizes[$0] == nil && !unavailableSizes.contains($0) }
        sizeTask?.cancel()
        sizeTask = nil
        guard !missing.isEmpty else { return }
        let sizes = sizes
        sizeTask = Task { [weak self] in
            let found = await sizes.estimatedSizes(of: missing)
            guard let self else { return }
            recordSizes(found, requested: missing, isComplete: !Task.isCancelled)
        }
    }

    private func recordSizes(_ found: [String: Int64], requested: [String], isComplete: Bool) {
        for (id, size) in found where size >= 0 {
            knownSizes[id] = size
        }
        if isComplete {
            for id in requested where knownSizes[id] == nil {
                unavailableSizes.insert(id)
            }
        }
        updateSummary(for: selectedAssetIDs)
    }

    /// Publishes the summary of `selected` if it changed.
    private func updateSummary(for selected: [String]) {
        let new = makeSummary(for: selected)
        if summary != new {
            summary = new
        }
    }

    /// The count and known size of `selected`, from the sizes estimated so far.
    func makeSummary(for selected: [String]) -> DeletionSummary {
        var bytes: Int64 = 0
        var unavailable = 0
        var pending = 0
        for id in selected {
            if let size = knownSizes[id] {
                bytes += size
            } else if unavailableSizes.contains(id) {
                unavailable += 1
            } else {
                pending += 1
            }
        }
        return DeletionSummary(
            photoCount: selected.count,
            knownBytes: bytes,
            unavailableCount: unavailable,
            pendingCount: pending
        )
    }
}

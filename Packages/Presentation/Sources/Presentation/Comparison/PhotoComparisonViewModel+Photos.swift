import Domain
import Foundation

extension PhotoComparisonViewModel {
    // MARK: - Photo details

    /// Looks up date, resolution, favorite, Live, file size and edits of the members, once per member set. Call when
    /// the screen appears and whenever the members change.
    public func loadDetails() async {
        let members = memberIDs
        guard !members.isEmpty, members != loadedMembers else { return }
        loadedMembers = members
        let library = list.library
        let sizes = list.sizes
        let edits = edits
        async let foundAssets = library.assets(withIDs: members)
        async let foundSizes = sizes.estimatedSizes(of: members)
        async let editedIDs = edits.editedAssetIDs(among: members)
        let assets = await foundAssets
        let fileSizes = await foundSizes
        let edited = await editedIDs
        guard !Task.isCancelled else {
            loadedMembers = []
            return
        }
        record(assets: assets, sizes: fileSizes, edited: edited, requested: members)
    }

    /// What the info panel shows about a member. Quality reasons come from the live suggestion; "Favorite" is a
    /// badge, so it is not repeated as a reason.
    public func info(for assetID: String) -> ComparisonPhotoInfo {
        var info = infos[assetID] ?? ComparisonPhotoInfo()
        if info.date == nil {
            info.date = list.photoDates[assetID]
        }
        let ranked = state?.suggestion.ranking.first { $0.assetID == assetID }
        info.reasons = (ranked?.reasons ?? []).filter { $0 != .favorite }
        return info
    }

    /// Whether the photo no longer exists (deleted outside the app); it can't be chosen.
    public func isMissing(_ assetID: String) -> Bool {
        list.missingAssetIDs.contains(assetID) || notFoundIDs.contains(assetID)
    }

    /// Whether the photo is selected for deletion.
    public func isSelected(_ assetID: String) -> Bool {
        state?.isSelected(assetID) ?? false
    }

    /// Whether the photo is the group's **Best** (the user's choice or the suggestion).
    public func isBest(_ assetID: String) -> Bool {
        state?.keeperID == assetID
    }

    /// The VoiceOver label of a photo: "Photo 2 of 5, taken 12 May 14:03, selected for deletion, Best shot".
    public func accessibilityLabel(for assetID: String) -> String {
        let position = (memberIDs.firstIndex(of: assetID) ?? 0) + 1
        return ClusterCardModel.photoAccessibilityLabel(
            position: position,
            count: memberIDs.count,
            dateText: info(for: assetID).date.map(ClusterCardModel.photoDateText),
            status: ClusterCardModel.PhotoStatus(isSelected: isSelected(assetID), isMissing: isMissing(assetID)),
            isBest: isBest(assetID)
        )
    }

    // MARK: - Actions

    /// "Keep This One": keeps the photo, marks it Best, and selects every other existing photo for deletion.
    public func keepOnly(_ assetID: String) {
        guard !isMissing(assetID) else { return }
        selection.keepOnly(assetID, in: clusterID, excluding: list.missingAssetIDs.union(notFoundIDs))
    }

    /// Selects the photo for deletion or keeps it. Selecting the last kept photo asks for confirmation first.
    public func toggle(_ assetID: String) {
        guard !isMissing(assetID) else { return }
        if selection.toggle(assetID, in: clusterID) == .needsConfirmation {
            isConfirmingDeleteAll = true
        }
    }

    /// "Mark as Best": the photo becomes the group's Best and is kept.
    public func markAsBest(_ assetID: String) {
        guard !isMissing(assetID) else { return }
        selection.markAsBest(assetID, in: clusterID)
    }

    /// The user confirmed deleting every photo of the group.
    public func confirmDeleteAll() {
        isConfirmingDeleteAll = false
        selection.confirmDeleteAll(clusterID)
    }

    // MARK: - Private

    /// Stores the looked-up details and which requested photos the library no longer has.
    private func record(assets: [PhotoAsset], sizes: [String: Int64], edited: Set<String>, requested: [String]) {
        var infos = infos
        for asset in assets {
            var info = ComparisonPhotoInfo()
            info.date = asset.creationDate
            info.pixelWidth = asset.pixelWidth
            info.pixelHeight = asset.pixelHeight
            info.isFavorite = asset.isFavorite
            info.isLivePhoto = asset.mediaSubtypes.contains(.livePhoto)
            info.isEdited = edited.contains(asset.id)
            if let size = sizes[asset.id], size >= 0 {
                info.fileSize = size
            }
            infos[asset.id] = info
        }
        if infos != self.infos {
            self.infos = infos
        }
        let notFound = Set(requested).subtracting(assets.map(\.id))
        if notFound != notFoundIDs {
            notFoundIDs = notFound
        }
    }
}

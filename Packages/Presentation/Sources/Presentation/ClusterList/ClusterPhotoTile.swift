import SwiftUI

/// One square photo of a group: the thumbnail, dimmed with a red checkmark while selected for deletion, the **Best**
/// badge on the keeper. Tapping it toggles the photo. Used by the group card and the group's own page.
struct ClusterPhotoTile: View {
    let photo: ClusterCardModel.Photo
    /// 1-based position in the group, for VoiceOver.
    let position: Int
    /// Number of photos in the group, for VoiceOver.
    let count: Int
    let state: ClusterSelectionState
    let pixelSize: CGSize
    let thumbnails: any ThumbnailLoading
    let onToggle: (String) -> Void
    let onCompare: () -> Void

    var body: some View {
        let isSelected = state.isSelected(photo.id)
        let isBest = state.keeperID == photo.id
        Button {
            onToggle(photo.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncThumbnail(
                        assetID: photo.id,
                        pixelSize: pixelSize,
                        isMissing: photo.isMissing,
                        loader: thumbnails
                    )
                }
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        SelectionCheck()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isBest {
                        BestBadge()
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(photo.isMissing)
        .accessibilityLabel(ClusterCardModel.photoAccessibilityLabel(
            position: position,
            count: count,
            dateText: photo.date.map(ClusterCardModel.photoDateText),
            status: ClusterCardModel.PhotoStatus(isSelected: isSelected, isMissing: photo.isMissing),
            isBest: isBest
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("clusters.action.toggle", bundle: .module)) { onToggle(photo.id) }
        .accessibilityAction(named: Text("clusters.action.compare", bundle: .module)) { onCompare() }
    }
}

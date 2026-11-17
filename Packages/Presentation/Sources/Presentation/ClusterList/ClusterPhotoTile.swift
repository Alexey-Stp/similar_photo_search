import SwiftUI

/// One square photo of a group. A photo selected for deletion is quietly dimmed and greyed out (no badge on every
/// photo); the keeper is highlighted with a green ring and the **Best** badge. Tapping it toggles the photo. Used by
/// the group card and the group's own page.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .saturation(isSelected ? 0 : 1)
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if isBest {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.green, lineWidth: 3)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
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

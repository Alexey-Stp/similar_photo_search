import Foundation

/// What one group card shows apart from the selection (which the card reads from its `ClusterSelectionState`).
///
/// A value, so cards compare cheaply (`Equatable`) and the list re-renders only cards whose content changed.
public struct ClusterCardModel: Hashable, Sendable, Identifiable {
    /// One thumbnail of the strip.
    public struct Photo: Hashable, Sendable, Identifiable {
        /// The photo's `localIdentifier`.
        public let id: String
        /// When it was taken, once looked up.
        public let date: Date?
        /// Whether the photo no longer exists in the library.
        public let isMissing: Bool

        /// Creates a photo.
        public init(id: String, date: Date?, isMissing: Bool) {
            self.id = id
            self.date = date
            self.isMissing = isMissing
        }
    }

    /// The cluster ID.
    public let id: String
    /// The members, in library order (newest first).
    public let photos: [Photo]
    /// Whether the photos are copies of the same image.
    public let isExactDuplicate: Bool
    /// Whether the group is flagged "Review recommended".
    public let needsReview: Bool

    /// Creates a card.
    public init(id: String, photos: [Photo], isExactDuplicate: Bool, needsReview: Bool) {
        self.id = id
        self.photos = photos
        self.isExactDuplicate = isExactDuplicate
        self.needsReview = needsReview
    }

    /// The date shown in the header: when the newest photo was taken.
    public var date: Date? {
        photos.lazy.compactMap(\.date).first
    }

    /// "12 May 2026, 14:03" (locale dependent), for the card header.
    public static func headerDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    /// "12 May 14:03" (locale dependent), for a photo's VoiceOver label.
    public static func photoDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// The VoiceOver label of a thumbnail: "Photo 2 of 5, taken 12 May 14:03, selected for deletion, Best shot".
    /// - Parameters:
    ///   - position: 1-based position in the group.
    ///   - count: Number of photos in the group.
    ///   - dateText: The formatted date (`photoDateText(_:)`), or `nil` if unknown.
    ///   - isSelected: Whether the photo is selected for deletion.
    ///   - isBest: Whether it is the suggested keeper.
    ///   - isMissing: Whether the photo no longer exists.
    public static func photoAccessibilityLabel(
        position: Int,
        count: Int,
        dateText: String?,
        isSelected: Bool,
        isBest: Bool,
        isMissing: Bool
    ) -> String {
        var parts = [String(localized: "clusters.photo.position \(position) \(count)", bundle: .module)]
        if let dateText {
            parts.append(String(localized: "clusters.photo.taken \(dateText)", bundle: .module))
        }
        if isMissing {
            parts.append(String(localized: "clusters.photo.unavailable", bundle: .module))
        } else if isSelected {
            parts.append(String(localized: "clusters.photo.selected", bundle: .module))
        } else {
            parts.append(String(localized: "clusters.photo.kept", bundle: .module))
        }
        if isBest {
            parts.append(String(localized: "clusters.photo.best", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }
}

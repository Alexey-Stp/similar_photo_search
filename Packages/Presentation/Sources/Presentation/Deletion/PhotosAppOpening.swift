import Foundation

/// Opens the Photos app (where Recently Deleted is). The app implements it with `photos-redirect://`, which is
/// undocumented: best effort, and `canOpenPhotos` is `false` when the system won't open it.
@MainActor
public protocol PhotosAppOpening: AnyObject {
    /// Whether the Photos app can be opened; the "Open Photos" button is hidden otherwise.
    var canOpenPhotos: Bool { get }

    /// Opens the Photos app. Does nothing if it can't be opened.
    func openPhotos()
}

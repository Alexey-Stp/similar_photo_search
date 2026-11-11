import Presentation
import UIKit

/// Opens the Photos app with its undocumented `photos-redirect://` scheme (SPS-25).
///
/// Best effort: `canOpenURL` needs `photos-redirect` in `LSApplicationQueriesSchemes`, and if the scheme stops
/// working the "Open Photos" button is simply hidden. It only switches to another app on the device; nothing is
/// loaded from the network.
@MainActor
final class UIKitPhotosAppOpener: PhotosAppOpening {
    private static let photosURL = URL(string: "photos-redirect://")

    /// Whether the system can open the Photos app.
    var canOpenPhotos: Bool {
        guard let url = Self.photosURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens the Photos app, if possible.
    func openPhotos() {
        guard let url = Self.photosURL, canOpenPhotos else { return }
        UIApplication.shared.open(url)
    }
}

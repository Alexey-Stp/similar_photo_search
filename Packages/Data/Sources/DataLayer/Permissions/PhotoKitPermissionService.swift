import Domain
import Foundation
import os
import Photos
#if canImport(UIKit)
import PhotosUI // declares PHPhotoLibrary.presentLimitedLibraryPicker(from:completionHandler:)
import UIKit
#endif

/// PhotoKit-backed `PhotoPermissionService`. Always uses the `.readWrite` access level,
/// because deleting photos needs it.
public final class PhotoKitPermissionService: PhotoPermissionService {
    private static let logger = Logger(subsystem: "com.similarphotos", category: "permissions")

    /// Creates the service.
    public init() {}

    /// Reads `PHPhotoLibrary.authorizationStatus(for: .readWrite)` without prompting.
    public func currentStatus() async -> PhotoLibraryAuthorization {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Shows the system prompt for `.readWrite` access if the user has not been asked yet.
    public func requestAccess() async -> PhotoLibraryAuthorization {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    /// Shows the system limited-library picker and returns when it is dismissed.
    /// Returns immediately if access is not limited or there is nothing to present from.
    public func presentLimitedPicker() async {
        #if canImport(UIKit)
        await Self.presentLimitedPickerOnMainActor()
        #endif
    }

    /// Maps a PhotoKit status to the domain status. Unknown future values count as denied.
    public static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    #if canImport(UIKit)
    @MainActor
    private static func presentLimitedPickerOnMainActor() async {
        // The picker only applies to limited access. If access changed (for example in Settings),
        // PhotoKit may never call the completion handler, so don't wait on it.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else {
            logger.info("Skipping the limited library picker: access is no longer limited")
            return
        }
        guard let presenter = topViewController() else {
            logger.error("Cannot show the limited library picker: no presenting view controller")
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The completion handler may run off the main thread, so the closure must not be main-actor isolated.
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { @Sendable _ in
                continuation.resume()
            }
        }
    }

    /// The top-most view controller of the foreground scene's key window.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}

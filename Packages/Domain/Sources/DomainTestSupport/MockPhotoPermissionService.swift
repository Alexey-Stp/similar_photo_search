import Domain
import Foundation

/// In-memory `PhotoPermissionService` for tests.
public actor MockPhotoPermissionService: PhotoPermissionService {
    /// Status returned by `currentStatus()`.
    public private(set) var status: PhotoLibraryAuthorization
    /// Status the mock switches to when `requestAccess()` is called.
    public var statusAfterRequest: PhotoLibraryAuthorization
    /// Photo count returned by `accessiblePhotoCount()`.
    public private(set) var photoCount: Int
    /// Photo count the mock switches to when `presentLimitedPicker()` is called, if set.
    public var photoCountAfterPicker: Int?

    /// Number of `requestAccess()` calls.
    public private(set) var requestAccessCallCount = 0
    /// Number of `accessiblePhotoCount()` calls.
    public private(set) var photoCountCallCount = 0
    /// Number of `presentLimitedPicker()` calls.
    public private(set) var presentLimitedPickerCallCount = 0

    /// Creates the mock.
    public init(
        status: PhotoLibraryAuthorization = .notDetermined,
        statusAfterRequest: PhotoLibraryAuthorization = .authorized,
        photoCount: Int = 0,
        photoCountAfterPicker: Int? = nil
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
        self.photoCount = photoCount
        self.photoCountAfterPicker = photoCountAfterPicker
    }

    /// Simulates the user changing the permission outside the app, for example in Settings.
    public func setStatus(_ newStatus: PhotoLibraryAuthorization) {
        status = newStatus
    }

    public func currentStatus() -> PhotoLibraryAuthorization {
        status
    }

    public func requestAccess() -> PhotoLibraryAuthorization {
        requestAccessCallCount += 1
        if status == .notDetermined {
            status = statusAfterRequest
        }
        return status
    }

    public func accessiblePhotoCount() -> Int {
        photoCountCallCount += 1
        return photoCount
    }

    public func presentLimitedPicker() {
        presentLimitedPickerCallCount += 1
        if let photoCountAfterPicker {
            photoCount = photoCountAfterPicker
        }
    }
}

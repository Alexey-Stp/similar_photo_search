import Domain
import Foundation

/// In-memory `PhotoPermissionService` for tests. The photo count lives in `MockPhotoLibraryRepository`.
public actor MockPhotoPermissionService: PhotoPermissionService {
    /// Status returned by `currentStatus()`.
    public private(set) var status: PhotoLibraryAuthorization
    /// Status the mock switches to when `requestAccess()` is called.
    public var statusAfterRequest: PhotoLibraryAuthorization

    /// Number of `requestAccess()` calls.
    public private(set) var requestAccessCallCount = 0
    /// Number of `presentLimitedPicker()` calls.
    public private(set) var presentLimitedPickerCallCount = 0

    /// Creates the mock.
    public init(
        status: PhotoLibraryAuthorization = .notDetermined,
        statusAfterRequest: PhotoLibraryAuthorization = .authorized
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
    }

    /// Simulates the user changing the permission outside the app, for example in Settings.
    public func setStatus(_ newStatus: PhotoLibraryAuthorization) {
        status = newStatus
    }

    /// Returns `status`.
    public func currentStatus() -> PhotoLibraryAuthorization {
        status
    }

    /// Switches a not-determined status to `statusAfterRequest` and returns the status.
    public func requestAccess() -> PhotoLibraryAuthorization {
        requestAccessCallCount += 1
        if status == .notDetermined {
            status = statusAfterRequest
        }
        return status
    }

    /// Records the call.
    public func presentLimitedPicker() {
        presentLimitedPickerCallCount += 1
    }
}

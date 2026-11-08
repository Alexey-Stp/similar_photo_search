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

    /// Whether the next `accessiblePhotoCount()` call should wait until `releaseHeldPhotoCount()`.
    private var holdsNextPhotoCount = false
    /// The suspended `accessiblePhotoCount()` call, if one is being held.
    private var heldPhotoCount: CheckedContinuation<Void, Never>?

    /// Whether an `accessiblePhotoCount()` call is currently suspended by `holdNextPhotoCount()`.
    public var isHoldingPhotoCount: Bool {
        heldPhotoCount != nil
    }

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

    /// Makes the next `accessiblePhotoCount()` call suspend until `releaseHeldPhotoCount()`,
    /// so tests can control the order in which overlapping requests finish.
    public func holdNextPhotoCount() {
        holdsNextPhotoCount = true
    }

    /// Resumes the held `accessiblePhotoCount()` call, if any.
    public func releaseHeldPhotoCount() {
        heldPhotoCount?.resume()
        heldPhotoCount = nil
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

    /// Returns `photoCount` as it was at the time of the call, waiting first if a hold is set.
    public func accessiblePhotoCount() async -> Int {
        photoCountCallCount += 1
        let count = photoCount
        if holdsNextPhotoCount {
            holdsNextPhotoCount = false
            await withCheckedContinuation { heldPhotoCount = $0 }
        }
        return count
    }

    /// Records the call and switches `photoCount` to `photoCountAfterPicker`, if set.
    public func presentLimitedPicker() {
        presentLimitedPickerCallCount += 1
        if let photoCountAfterPicker {
            photoCount = photoCountAfterPicker
        }
    }
}

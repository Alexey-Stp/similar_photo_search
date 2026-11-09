import Domain
import Foundation
import Photos

/// `LibraryChangeObserving` over a `PHPhotoLibraryChangeObserver`: library changes while the app runs, debounced.
///
/// PhotoKit calls `photoLibraryDidChange(_:)` on a background queue; the callback only pokes a `DebouncedSignal`,
/// which never touches caller state. Consumers read `changes()` on their own actor. The observer registers on the
/// first `changes()` call (after the user granted access, never at launch) and unregisters in `deinit`.
/// PhotoKit delivers nothing while the app is suspended, so in practice the stream fires in the foreground.
public final class PhotoKitLibraryObserver: NSObject, PHPhotoLibraryChangeObserver, LibraryChangeObserving,
    @unchecked Sendable {
    // @unchecked: `isRegistered` is guarded by `lock`; `signal` is Sendable.

    /// The quiet period after the last change before the stream fires.
    public static let defaultDebounce = Duration.seconds(1)

    private let signal: DebouncedSignal
    private let lock = NSLock()
    private var isRegistered = false

    /// Creates an observer; it does not register with PhotoKit yet.
    public init(debounce: Duration = PhotoKitLibraryObserver.defaultDebounce) {
        signal = DebouncedSignal(interval: debounce)
        super.init()
    }

    /// Unregisters from PhotoKit (if registered) and finishes every open stream.
    deinit {
        if isRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
        signal.finish()
    }

    /// A new debounced stream of library changes. Registers with PhotoKit on the first call.
    public func changes() -> AsyncStream<Void> {
        registerIfNeeded()
        return signal.stream()
    }

    /// Called by PhotoKit on a background queue.
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        signal.signal()
    }

    /// Registers with `PHPhotoLibrary.shared()` once, on the first call.
    private func registerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else { return }
        isRegistered = true
        PHPhotoLibrary.shared().register(self)
    }
}

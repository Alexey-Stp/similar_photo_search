import CoreGraphics
import DataLayer
import Foundation
import ImageIO

/// Thread-safe `ImageRequesting` fake: answers at once, holds requests until a test releases them, or reports the
/// asset as missing. Records requests, cancellations and the highest number of requests held at the same time.
final class MockImageRequester: ImageRequesting, @unchecked Sendable {
    /// How the fake answers a request.
    enum Behavior {
        /// Calls the handler with each result, in order, before `requestImage` returns.
        case respond([ImageRequestResult])
        /// Keeps the request open until `releaseFirstHeld(with:)` or `releaseHeld(assetID:with:)`.
        case hold
        /// No photo has this identifier.
        case missing
    }

    private struct HeldRequest {
        let requestID: ImageRequestID
        let assetID: String
        let handler: @Sendable (ImageRequestResult) -> Void
    }

    private let lock = NSLock()
    private let defaultBehavior: Behavior
    private var behaviors: [String: Behavior]
    private var held: [HeldRequest] = []
    private var nextRequestID: ImageRequestID = 1
    private var requested: [String] = []
    private var sizes: [CGSize] = []
    private var cancelled: [ImageRequestID] = []
    private var maxHeld = 0

    init(defaultBehavior: Behavior, behaviors: [String: Behavior] = [:]) {
        self.defaultBehavior = defaultBehavior
        self.behaviors = behaviors
    }

    /// Asset IDs requested so far, in order.
    var requestedAssetIDs: [String] { locked { requested } }
    /// Target sizes of the requests, in order.
    var requestedSizes: [CGSize] { locked { sizes } }
    /// Whether at least one request is held and every held request was cancelled.
    var allHeldRequestsCancelled: Bool {
        locked { !held.isEmpty && held.allSatisfy { cancelled.contains($0.requestID) } }
    }
    /// Request IDs passed to `cancelRequest`.
    var cancelledRequestIDs: [ImageRequestID] { locked { cancelled } }
    /// Requests currently held open.
    var heldCount: Int { locked { held.count } }
    /// The most requests that were held open at the same time.
    var maxHeldAtOnce: Int { locked { maxHeld } }

    func requestImage(
        assetID: String,
        targetSize: CGSize,
        resultHandler: @escaping @Sendable (ImageRequestResult) -> Void
    ) -> ImageRequestID? {
        lock.lock()
        let behavior = behaviors[assetID] ?? defaultBehavior
        if case .missing = behavior {
            lock.unlock()
            return nil
        }
        let requestID = nextRequestID
        nextRequestID += 1
        requested.append(assetID)
        sizes.append(targetSize)
        switch behavior {
        case .respond(let results):
            lock.unlock()
            for result in results {
                resultHandler(result)
            }
        case .hold:
            held.append(HeldRequest(requestID: requestID, assetID: assetID, handler: resultHandler))
            maxHeld = max(maxHeld, held.count)
            lock.unlock()
        case .missing:
            lock.unlock()
        }
        return requestID
    }

    func cancelRequest(_ requestID: ImageRequestID) {
        locked { cancelled.append(requestID) }
    }

    /// Answers the oldest held request. Returns its asset ID, or `nil` if none is held.
    @discardableResult
    func releaseFirstHeld(with result: ImageRequestResult) -> String? {
        lock.lock()
        guard !held.isEmpty else {
            lock.unlock()
            return nil
        }
        let request = held.removeFirst()
        lock.unlock()
        request.handler(result)
        return request.assetID
    }

    /// Answers every held request, for example to deliver late callbacks after a cancellation.
    func releaseAllHeld(with result: ImageRequestResult) {
        lock.lock()
        let requests = held
        held = []
        lock.unlock()
        for request in requests {
            request.handler(result)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Small helpers shared by the image-loading tests.
enum ImageTestSupport {
    /// A 4×4 bitmap.
    static func makeImage() throws -> CGImage {
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let image = context?.makeImage() else {
            throw CocoaError(.featureUnsupported)
        }
        return image
    }

    /// A successful callback with a small image.
    static func success(orientation: CGImagePropertyOrientation = .up) throws -> ImageRequestResult {
        ImageRequestResult(image: LoadedImage(cgImage: try makeImage(), orientation: orientation))
    }

    /// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
    static func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @Sendable () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}

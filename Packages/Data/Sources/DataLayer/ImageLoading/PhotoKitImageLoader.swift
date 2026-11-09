import CoreGraphics
import Foundation

/// `ImageLoading` over PhotoKit: downscaled, local-only images for analysis.
///
/// Holds no state of its own; every request is independent. Uses `PHImageManager.default()` through
/// `PhotoKitImageRequester` (not `PHCachingImageManager`, which is for UI thumbnails).
public final class PhotoKitImageLoader: ImageLoading {
    private let requester: any ImageRequesting

    /// Creates a loader over PhotoKit.
    public convenience init() {
        self.init(requester: PhotoKitImageRequester())
    }

    /// Creates a loader over any image-request API, for example a mock in tests.
    public init(requester: any ImageRequesting) {
        self.requester = requester
    }

    /// Loads one photo. Cancelling the calling task cancels the PhotoKit request and throws `.cancelled` at once.
    public func loadImage(assetID: String, targetSize: CGSize) async throws -> LoadedImage {
        let pending = PendingImageRequest(requester: requester)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.start(continuation) else { return }
                let requestID = requester.requestImage(assetID: assetID, targetSize: targetSize) { result in
                    pending.handle(result)
                }
                if let requestID {
                    pending.attach(requestID)
                } else {
                    pending.finish(.failure(.notFound))
                }
            }
        } onCancel: {
            pending.cancel()
        }
    }

    /// Loads several photos through a bounded window; see `ImageLoading.loadBatch(_:targetSize:maxConcurrent:)`.
    public func loadBatch(
        _ assetIDs: [String],
        targetSize: CGSize,
        maxConcurrent: Int
    ) -> AsyncStream<ImageLoadOutcome> {
        let window = ImageBatchWindow(assetIDs: assetIDs, width: max(1, maxConcurrent)) { [self] assetID in
            do {
                let image = try await loadImage(assetID: assetID, targetSize: targetSize)
                return ImageLoadOutcome(assetID: assetID, result: .success(image))
            } catch let error as ImageLoadError {
                return ImageLoadOutcome(assetID: assetID, result: .failure(error))
            } catch {
                return ImageLoadOutcome(assetID: assetID, result: .failure(.cancelled))
            }
        }
        return AsyncStream(
            unfolding: { await window.next() },
            onCancel: { Task { await window.cancel() } }
        )
    }

    /// Maps one callback to the request's final result, or `nil` to keep waiting.
    ///
    /// Requests use `.highQualityFormat`, so PhotoKit calls back once. That callback is final: a degraded stand-in
    /// is not good enough for analysis, so it counts as a skip rather than something to wait for (waiting could hang).
    static func outcome(of result: ImageRequestResult) -> Result<LoadedImage, ImageLoadError> {
        if result.isCancelled {
            return .failure(.cancelled)
        }
        if let image = result.image, !result.isDegraded {
            return .success(image)
        }
        return .failure(result.isInCloud ? .iCloudOnly : .decodeFailed)
    }
}

/// One in-flight request. Resumes its continuation exactly once, whatever order the callback, the request ID and a
/// cancellation arrive in; later callbacks are ignored.
private final class PendingImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let requester: any ImageRequesting
    private var continuation: CheckedContinuation<LoadedImage, any Error>?
    private var requestID: ImageRequestID?
    private var isCancelled = false
    private var isFinished = false

    init(requester: any ImageRequesting) {
        self.requester = requester
    }

    /// Stores the continuation. Returns `false` (and resumes it with `.cancelled`) if the task was already cancelled.
    func start(_ continuation: CheckedContinuation<LoadedImage, any Error>) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(throwing: ImageLoadError.cancelled)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    /// Records the PhotoKit request ID; cancels the request right away if the task was cancelled before it existed.
    func attach(_ requestID: ImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let cancelNow = isCancelled
        lock.unlock()
        if cancelNow {
            requester.cancelRequest(requestID)
        }
    }

    /// Handles a PhotoKit callback.
    func handle(_ result: ImageRequestResult) {
        finish(PhotoKitImageLoader.outcome(of: result))
    }

    /// Resumes the continuation with `result`, unless it was already resumed.
    func finish(_ result: Result<LoadedImage, ImageLoadError>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        switch result {
        case .success(let image):
            continuation?.resume(returning: image)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    /// Cancels the PhotoKit request (if it exists yet) and resumes with `.cancelled`, unless already finished.
    func cancel() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        isCancelled = true
        let requestID = requestID
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        if let requestID {
            requester.cancelRequest(requestID)
        }
        continuation?.resume(throwing: ImageLoadError.cancelled)
    }
}

/// Feeds a batch through at most `width` loads at a time, and only as fast as the consumer takes outcomes:
/// in-flight loads plus outcomes not yet taken never exceed `width`, so loaded images can't pile up in memory.
private actor ImageBatchWindow {
    private let width: Int
    private let load: @Sendable (String) async -> ImageLoadOutcome
    private var pending: ArraySlice<String>
    private var inFlight: [Int: Task<Void, Never>] = [:]
    private var ready: [ImageLoadOutcome] = []
    private var waiter: CheckedContinuation<ImageLoadOutcome?, Never>?
    private var nextKey = 0
    private var isCancelled = false

    init(assetIDs: [String], width: Int, load: @escaping @Sendable (String) async -> ImageLoadOutcome) {
        self.pending = assetIDs[...]
        self.width = width
        self.load = load
    }

    /// The next outcome, or `nil` when every photo was delivered or the batch was cancelled.
    func next() async -> ImageLoadOutcome? {
        guard !isCancelled else { return nil }
        if !ready.isEmpty {
            let outcome = ready.removeFirst()
            fill()
            return outcome
        }
        fill()
        guard !inFlight.isEmpty else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    /// Stops the batch: cancels in-flight loads (and so their PhotoKit requests) and ends the stream.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        pending = []
        ready = []
        for task in inFlight.values {
            task.cancel()
        }
        waiter?.resume(returning: nil)
        waiter = nil
    }

    /// Starts loads until the window is full.
    private func fill() {
        while !isCancelled, inFlight.count + ready.count < width, let assetID = pending.popFirst() {
            let key = nextKey
            nextKey += 1
            let load = load
            // The task inherits the actor's isolation: `load` runs off the actor, `complete` back on it.
            inFlight[key] = Task {
                let outcome = await load(assetID)
                self.complete(key: key, outcome: outcome)
            }
        }
    }

    /// Hands a finished load to a waiting consumer, or keeps it until the consumer asks.
    private func complete(key: Int, outcome: ImageLoadOutcome) {
        inFlight[key] = nil
        guard !isCancelled else { return }
        if let waiter {
            self.waiter = nil
            fill()
            waiter.resume(returning: outcome)
        } else {
            ready.append(outcome)
        }
    }
}

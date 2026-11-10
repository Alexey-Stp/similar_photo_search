import Foundation

/// The bounded image work of a scan and its thermal pause.
extension ScanRun {
    // MARK: - Bounded image work

    /// Runs `work` for every asset with at most the recommended width at a time, waiting while the scan is paused.
    ///
    /// Photos deleted during the scan are never started. Returns every result that arrived (also after a
    /// cancellation, so finished work can be saved) and whether the scan was cancelled.
    func runBounded<Output: Sendable>(
        _ assets: [PhotoAsset],
        countsAsProgress: Bool,
        work: @escaping @Sendable (PhotoAsset) async throws -> Output
    ) async -> (results: [String: Output], wasCancelled: Bool) {
        guard !assets.isEmpty else { return ([:], Task.isCancelled) }
        var results: [String: Output] = [:]
        var wasCancelled = false
        let exclusions = exclusions
        await withTaskGroup(of: (String, Output?).self) { group in
            var running = 0
            var index = 0
            while index < assets.count {
                let width: Int
                do {
                    width = try await waitForWidth()
                } catch {
                    wasCancelled = true
                    break
                }
                if running >= width, let (id, output) = await group.next() {
                    running -= 1
                    record(id: id, output: output, into: &results, countsAsProgress: countsAsProgress)
                    continue
                }
                let asset = assets[index]
                index += 1
                guard !exclusions.contains(asset.id) else { continue }
                group.addTask {
                    // Checked again here: the photo may have been deleted while this task waited to start.
                    guard !exclusions.contains(asset.id) else { return (asset.id, nil) }
                    return (asset.id, try? await work(asset))
                }
                running += 1
            }
            if wasCancelled || Task.isCancelled {
                group.cancelAll()
            }
            for await (id, output) in group {
                record(id: id, output: output, into: &results, countsAsProgress: countsAsProgress)
            }
        }
        return (results, wasCancelled || Task.isCancelled)
    }

    /// Stores one finished result and advances the progress.
    func record<Output>(
        id: String,
        output: Output?,
        into results: inout [String: Output],
        countsAsProgress: Bool
    ) {
        guard let output else { return }
        results[id] = output
        if countsAsProgress {
            progress.processed += 1
            report()
        }
    }

    // MARK: - Throttling

    /// The current width; waits (phase `.throttled`) while it is 0. Throws `CancellationError` if cancelled.
    func waitForWidth() async throws -> Int {
        var width = progress.conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency)
        guard width == 0 else { return width }
        let resumedPhase = progress.phase
        progress.phase = .throttled
        report(force: true)
        while width == 0 {
            try Task.checkCancellation()
            let id = nextWaiterID
            nextWaiterID += 1
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        pauseWaiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancelPauseWaiter(id) }
            }
            width = progress.conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency)
        }
        progress.phase = resumedPhase
        report(force: true)
        return width
    }

    /// New conditions from the thermal monitor: published, and a paused scan goes on if they allow it.
    func conditionsChanged(_ conditions: ScanConditions) {
        guard conditions != progress.conditions else { return }
        progress.conditions = conditions
        report(force: true)
        if conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency) > 0 {
            let waiters = pauseWaiters.values
            pauseWaiters = [:]
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    /// Ends one wait because its task was cancelled.
    func cancelPauseWaiter(_ id: UInt64) {
        pauseWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Ends every wait.
    func resumeAllPauseWaiters(throwing error: any Error) {
        let waiters = pauseWaiters.values
        pauseWaiters = [:]
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
}

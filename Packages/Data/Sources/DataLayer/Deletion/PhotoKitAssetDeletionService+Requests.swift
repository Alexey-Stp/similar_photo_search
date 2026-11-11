import Domain
import Foundation
import Photos

/// What the delete requests reported, before the deletion is confirmed by a re-fetch.
struct DeletionRequestReport: Sendable, Hashable {
    /// IDs that a request PhotoKit completed without an error actually submitted for deletion.
    var succeeded: [String] = []
    /// IDs in requests that failed, with the reason.
    var failed: [String: DeletionError] = [:]
    /// The user tapped "Don't Allow"; no later request was made.
    var cancelled = false
}

/// How one failed `performChanges` call is reported.
enum DeletionRequestFailure: Sendable, Hashable {
    /// `PHPhotosError.userCancelled`: a normal outcome, not an error.
    case cancelledByUser
    /// Every ID in the request failed with this reason.
    case failed(DeletionError)
}

extension PhotoKitAssetDeletionService {
    /// One request for every eligible ID; on a retryable failure, and only with the feature flag on, chunked requests.
    func performRequests(for eligible: [String]) async -> DeletionRequestReport {
        let report = await performRequest(for: eligible)
        guard let chunkSize = chunkSizeAfterFailure, Self.isRetryable(report) else { return report }
        Self.logger.notice("Single deletion request failed; retrying in chunks of \(chunkSize)")
        return await performChunkedRequests(for: eligible, chunkSize: chunkSize)
    }

    /// Requests of `chunkSize` IDs in order. Stops at a user cancel; a failed chunk does not stop the others.
    func performChunkedRequests(for eligible: [String], chunkSize: Int) async -> DeletionRequestReport {
        var report = DeletionRequestReport()
        for start in stride(from: 0, to: eligible.count, by: chunkSize) {
            let chunk = Array(eligible[start..<min(start + chunkSize, eligible.count)])
            let chunkReport = await performRequest(for: chunk)
            report.succeeded += chunkReport.succeeded
            report.failed.merge(chunkReport.failed) { _, new in new }
            if chunkReport.cancelled {
                report.cancelled = true
                break
            }
        }
        return report
    }

    /// One `performChanges` call for `ids`.
    func performRequest(for ids: [String]) async -> DeletionRequestReport {
        do {
            let submitted = try await library.deleteAssets(withIDs: ids)
            // An ID the change block did not find vanished after the check: this call did not delete it.
            var report = DeletionRequestReport()
            for id in ids {
                if submitted.contains(id) {
                    report.succeeded.append(id)
                } else {
                    report.failed[id] = .unavailable
                }
            }
            return report
        } catch {
            switch Self.failure(for: error) {
            case .cancelledByUser:
                return DeletionRequestReport(cancelled: true)
            case .failed(let reason):
                return DeletionRequestReport(failed: Dictionary(uniqueKeysWithValues: ids.map { ($0, reason) }))
            }
        }
    }

    /// Maps an error from `performChanges`: `userCancelled` is a cancel, `accessUserDenied`/`accessRestricted` are
    /// `.permissionDenied`, anything else is `.unknown` with the error's domain and code.
    static func failure(for error: any Error) -> DeletionRequestFailure {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain {
            switch PHPhotosError.Code(rawValue: nsError.code) {
            case .userCancelled:
                return .cancelledByUser
            case .accessUserDenied, .accessRestricted:
                return .failed(.permissionDenied)
            default:
                break
            }
        }
        return .failed(.unknown("\(nsError.domain) \(nsError.code)"))
    }

    /// A failed single request is worth retrying in chunks unless it was cancelled or lacked access.
    static func isRetryable(_ report: DeletionRequestReport) -> Bool {
        guard !report.cancelled, !report.failed.isEmpty else { return false }
        return !report.failed.values.contains(.permissionDenied)
    }
}

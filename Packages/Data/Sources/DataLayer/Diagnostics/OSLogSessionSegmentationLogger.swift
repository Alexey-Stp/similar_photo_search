import Domain
import os

/// `SessionSegmentationLogging` backed by `os.Logger` (category `sessions`).
///
/// Only counts are logged, never asset identifiers or dates. Oversized-session splits are always logged; the
/// end-of-run summary (how many photos skipped Vision as single-photo sessions) is logged only in debug builds,
/// so the saving can be measured on real libraries.
public struct OSLogSessionSegmentationLogger: SessionSegmentationLogging {
    private static let logger = Logger(subsystem: "com.similarphotos", category: "sessions")

    /// Creates the logger.
    public init() {}

    public func didSplitOversizedSession(assetCount: Int, partSizes: [Int]) {
        let sizes = partSizes.map(String.init).joined(separator: ", ")
        Self.logger.notice(
            "Split an oversized session of \(assetCount, privacy: .public) photos into [\(sizes, privacy: .public)]"
        )
    }

    public func didFinish(_ summary: SessionSegmentationSummary) {
        #if DEBUG
        Self.logger.debug("""
            Sessions: \(summary.sessionCount, privacy: .public), \
            single-photo (skipped Vision): \(summary.singlePhotoSessionCount, privacy: .public), \
            skipped (no date): \(summary.skippedNoDateCount, privacy: .public), \
            oversized splits: \(summary.oversizedSplitCount, privacy: .public)
            """)
        #endif
    }
}

import Foundation

/// Receives diagnostics from `SessionSegmenter`.
///
/// Domain has no logging framework, so the app injects an implementation backed by `os.Logger`.
/// Calls are made synchronously from the consuming task and must return quickly.
public protocol SessionSegmentationLogging: Sendable {
    /// A run of `assetCount` photos was larger than `maxSessionSize` and was split into sessions of `partSizes`.
    func didSplitOversizedSession(assetCount: Int, partSizes: [Int])

    /// Segmentation reached the end of the input.
    func didFinish(_ summary: SessionSegmentationSummary)
}

/// A `SessionSegmentationLogging` that drops everything.
public struct SilentSessionSegmentationLogger: SessionSegmentationLogging {
    /// Creates the logger.
    public init() {}

    public func didSplitOversizedSession(assetCount: Int, partSizes: [Int]) {}

    public func didFinish(_ summary: SessionSegmentationSummary) {}
}

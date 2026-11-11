import CoreGraphics
import Foundation
import Observation

/// Zoom and pan of one image, or of both images of the side-by-side mode, which share one `ZoomState` so they
/// zoom and pan together.
///
/// The view applies `scaleEffect(scale)` around the centre and then `offset(offset)`. Offsets are clamped so the
/// image edge never moves inside the frame. A gesture changes the state live (`magnify`, `pan`) relative to where
/// it started, and `endGesture()` commits it.
@Observable
@MainActor
public final class ZoomState {
    /// The largest zoom.
    public nonisolated static let maxScale: CGFloat = 4
    /// The zoom a double tap switches to.
    public nonisolated static let doubleTapScale: CGFloat = 2.5
    /// How much one VoiceOver zoom action zooms in or out.
    public nonisolated static let accessibilityStep: CGFloat = 1.5

    /// The current zoom, 1…`maxScale`.
    public private(set) var scale: CGFloat = 1
    /// The current pan, in points.
    public private(set) var offset: CGSize = .zero

    @ObservationIgnored private var baseScale: CGFloat = 1
    @ObservationIgnored private var baseOffset: CGSize = .zero

    /// Creates an unzoomed state.
    public init() {}

    /// Whether the image is zoomed in (then dragging pans instead of paging or dismissing).
    public var isZoomed: Bool { scale > 1.001 }

    /// A pinch in progress: `factor` relative to the zoom when the pinch began. The pan grows with the zoom.
    public func magnify(by factor: CGFloat, content: CGSize) {
        let newScale = Self.clampedScale(baseScale * factor)
        let ratio = baseScale > 0 ? newScale / baseScale : 1
        scale = newScale
        offset = Self.clampedOffset(
            CGSize(width: baseOffset.width * ratio, height: baseOffset.height * ratio),
            scale: newScale,
            content: content
        )
    }

    /// A drag in progress while zoomed: `translation` since the drag began.
    public func pan(by translation: CGSize, content: CGSize) {
        guard isZoomed else { return }
        let moved = CGSize(width: baseOffset.width + translation.width, height: baseOffset.height + translation.height)
        offset = Self.clampedOffset(moved, scale: scale, content: content)
    }

    /// A pinch or drag ended: keeps the result, or snaps back to 1× when barely zoomed.
    public func endGesture() {
        if scale <= 1.01 {
            reset()
        } else {
            baseScale = scale
            baseOffset = offset
        }
    }

    /// Double tap: zooms to `doubleTapScale` around `point` (in the frame of size `frame`), or back to 1×.
    public func toggleZoom(at point: CGPoint, frame: CGSize, content: CGSize) {
        guard !isZoomed else {
            reset()
            return
        }
        let target = Self.doubleTapScale
        let centered = CGSize(
            width: (frame.width / 2 - point.x) * (target - 1),
            height: (frame.height / 2 - point.y) * (target - 1)
        )
        set(scale: target, offset: Self.clampedOffset(centered, scale: target, content: content))
    }

    /// The VoiceOver zoom action: one step in or out around the current centre.
    public func accessibilityZoom(zoomIn: Bool, content: CGSize) {
        let target = Self.clampedScale(zoomIn ? scale * Self.accessibilityStep : scale / Self.accessibilityStep)
        guard target > 1.01 else {
            reset()
            return
        }
        set(scale: target, offset: Self.clampedOffset(offset, scale: target, content: content))
    }

    /// Back to 1×, centred.
    public func reset() {
        set(scale: 1, offset: .zero)
    }

    /// `scale` within 1…`maxScale`; anything not finite becomes 1.
    public nonisolated static func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(maxScale, max(1, scale))
    }

    /// `offset` limited so an image of size `content` (centred, zoomed by `scale`) still covers its frame.
    public nonisolated static func clampedOffset(_ offset: CGSize, scale: CGFloat, content: CGSize) -> CGSize {
        let limitX = max(0, (scale - 1) * content.width / 2)
        let limitY = max(0, (scale - 1) * content.height / 2)
        return CGSize(
            width: min(limitX, max(-limitX, offset.width.isFinite ? offset.width : 0)),
            height: min(limitY, max(-limitY, offset.height.isFinite ? offset.height : 0))
        )
    }

    /// Publishes the zoom and pan (only when they change) and makes them the base of the next gesture.
    private func set(scale newScale: CGFloat, offset newOffset: CGSize) {
        if scale != newScale {
            scale = newScale
        }
        if offset != newOffset {
            offset = newOffset
        }
        baseScale = newScale
        baseOffset = newOffset
    }
}

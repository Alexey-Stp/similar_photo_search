import CoreGraphics
import Presentation
import SwiftUI
import Testing

/// Zoom, pan and their limits (SPS-22).
@MainActor
struct ZoomStateTests {
    private let content = CGSize(width: 300, height: 200)

    @Test func scaleStaysBetweenOneAndTheMaximum() {
        #expect(ZoomState.clampedScale(0.3) == 1)
        #expect(ZoomState.clampedScale(10) == ZoomState.maxScale)
        #expect(ZoomState.clampedScale(.nan) == 1)
        #expect(ZoomState.clampedScale(2) == 2)
    }

    @Test func offsetsKeepTheImageCoveringItsFrame() {
        let clamped = ZoomState.clampedOffset(CGSize(width: 500, height: -500), scale: 2, content: content)
        #expect(clamped == CGSize(width: 150, height: -100))
        #expect(ZoomState.clampedOffset(CGSize(width: 40, height: 40), scale: 1, content: content) == .zero)
    }

    @Test func doubleTapZoomsAroundTheTapAndBack() {
        let zoom = ZoomState()
        zoom.toggleZoom(at: CGPoint(x: 100, y: 100), frame: content, content: content)
        #expect(zoom.scale == ZoomState.doubleTapScale)
        // (150 - 100) × 1.5 = 75 to the right; the tap was on the vertical centre.
        #expect(zoom.offset == CGSize(width: 75, height: 0))

        zoom.toggleZoom(at: .zero, frame: content, content: content)
        #expect(zoom.scale == 1)
        #expect(zoom.offset == .zero)
    }

    @Test func pinchIsRelativeToTheStartAndCommitsOnEnd() {
        let zoom = ZoomState()
        zoom.magnify(by: 2, content: content)
        zoom.magnify(by: 3, content: content)
        #expect(zoom.scale == 3)
        zoom.endGesture()
        zoom.magnify(by: 2, content: content)
        #expect(zoom.scale == ZoomState.maxScale)
    }

    @Test func aBarelyZoomedPinchSnapsBack() {
        let zoom = ZoomState()
        zoom.magnify(by: 1.005, content: content)
        zoom.endGesture()
        #expect(!zoom.isZoomed)
        #expect(zoom.scale == 1)
    }

    @Test func dragPansOnlyWhileZoomedAndWithinLimits() {
        let zoom = ZoomState()
        zoom.pan(by: CGSize(width: 50, height: 0), content: content)
        #expect(zoom.offset == .zero)

        zoom.magnify(by: 2, content: content)
        zoom.endGesture()
        zoom.pan(by: CGSize(width: 50, height: 400), content: content)
        #expect(zoom.offset == CGSize(width: 50, height: 100))
    }

    @Test func voiceOverZoomStepsInAndOutToOne() {
        let zoom = ZoomState()
        zoom.accessibilityZoom(zoomIn: true, content: content)
        #expect(zoom.scale == ZoomState.accessibilityStep)
        zoom.accessibilityZoom(zoomIn: false, content: content)
        #expect(zoom.scale == 1)
        #expect(!zoom.isZoomed)
    }

    @Test func twoPanesSharingOneStateZoomTogether() {
        let shared = ZoomState()
        let left = shared
        let right = shared
        left.magnify(by: 2, content: content)
        #expect(right.scale == 2)
    }
}

/// Screen-size requests and the side-by-side rule (SPS-22).
struct ComparisonLayoutTests {
    @Test func pixelSizesAreScreenPixelsAndNeverHuge() {
        #expect(ComparisonLayout.pixelSize(points: CGSize(width: 390, height: 844), scale: 3)
            == CGSize(width: 1_170, height: 2_532))
        #expect(ComparisonLayout.pixelSize(points: CGSize(width: 5_000, height: 0), scale: 2)
            == CGSize(width: ComparisonLayout.maxPixelSide, height: 1))
        #expect(ComparisonLayout.pixelSize(points: CGSize(width: 100, height: 100), scale: .nan)
            == CGSize(width: 100, height: 100))
    }

    @Test func sideBySideFitsOnRegularWidthOrCompactHeight() {
        #expect(ComparisonLayout.canShowSideBySide(horizontal: .regular, vertical: .regular))
        #expect(ComparisonLayout.canShowSideBySide(horizontal: .compact, vertical: .compact))
        #expect(!ComparisonLayout.canShowSideBySide(horizontal: .compact, vertical: .regular))
    }

    @Test func imagesFitWithoutCropping() {
        let image = CGSize(width: 4_000, height: 3_000)
        let fitted = ComparisonLayout.fittedSize(of: image, in: CGSize(width: 400, height: 800))
        #expect(fitted == CGSize(width: 400, height: 300))
    }
}

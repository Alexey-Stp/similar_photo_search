import SwiftUI

/// One photo that zooms with a pinch, a double tap (1× ↔ 2.5× around the tap) or the VoiceOver zoom action, and
/// pans with a drag while zoomed. Two `ZoomableImage`s given the same `ZoomState` zoom and pan together.
///
/// While not zoomed, the drag is off, so the pager can swipe and the screen can be swiped down to dismiss.
struct ZoomableImage: View {
    let image: Thumbnail
    let zoom: ZoomState
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The image, fitted into the frame, scaled and moved by `zoom`.
    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let content = ComparisonLayout.fittedSize(of: image.uprightSize, in: frame)
            Image(decorative: image.cgImage, scale: 1, orientation: image.orientation)
                .resizable()
                .scaledToFit()
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(zoom.scale)
                .offset(ZoomState.clampedOffset(zoom.offset, scale: zoom.scale, content: content))
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                        zoom.toggleZoom(at: location, frame: frame, content: content)
                    }
                }
                .gesture(magnify(content: content))
                .gesture(pan(content: content), including: zoom.isZoomed ? .all : .subviews)
                .accessibilityZoomAction { action in
                    zoom.accessibilityZoom(zoomIn: action.direction == .zoomIn, content: content)
                }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private func magnify(content: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom.magnify(by: value.magnification, content: content) }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { zoom.endGesture() }
            }
    }

    private func pan(content: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in zoom.pan(by: value.translation, content: content) }
            .onEnded { _ in zoom.endGesture() }
    }
}

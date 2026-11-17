import SwiftUI

extension View {
    /// Liquid Glass in `shape` on iOS 26, the regular material before it. For bars and controls that float over
    /// content: the selection bar, the comparison's top bar and filmstrip.
    func glassBackground<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }
}

private struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// A 44-point glass circle with an SF Symbol, for controls floating over a photo (Close, Side by Side). The
/// label's title is the VoiceOver label.
struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassBackground(in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}

/// The glass circle as an on/off switch: filled with the label colour while on.
struct GlassCircleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background {
                    if configuration.isOn {
                        Circle().fill(.primary)
                    }
                }
                .glassBackground(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

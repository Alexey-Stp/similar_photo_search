import SwiftUI

/// Persistent banner shown on Home under limited photo access.
/// Explains that results may be incomplete and offers to change the selection or open Settings.
struct LimitedAccessBanner: View {
    let photoCount: Int
    let onManage: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("limitedBanner.message \(photoCount)", bundle: .module)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onManage) {
            Text("limitedBanner.manage", bundle: .module)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(Text("limitedBanner.manage.hint", bundle: .module))
        Button(action: onSettings) {
            Text("limitedBanner.settings", bundle: .module)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(Text("limitedBanner.settings.hint", bundle: .module))
    }
}

#Preview("Light") {
    LimitedAccessBanner(photoCount: 42, onManage: {}, onSettings: {})
}

#Preview("Dark") {
    LimitedAccessBanner(photoCount: 1, onManage: {}, onSettings: {})
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    LimitedAccessBanner(photoCount: 1_234, onManage: {}, onSettings: {})
        .dynamicTypeSize(.accessibility5)
}

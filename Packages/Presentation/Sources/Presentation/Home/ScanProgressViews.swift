import Domain
import SwiftUI

/// A circular progress ring with the percentage in the middle. Scales with Dynamic Type.
struct ProgressRing: View {
    /// 0…1.
    let fraction: Double
    /// The text in the middle, for example "42 %".
    let label: String
    /// While the results are saved after 100 %: a spinner replaces the percentage.
    var isFinishing = false

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 184
    @ScaledMetric(relativeTo: .largeTitle) private var lineWidth: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
            if isFinishing {
                ProgressView()
                    .controlSize(.large)
            } else {
                Text(label)
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(lineWidth)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A one-line progress bar for the top of a screen while a scan runs: "Scanning… 4,210 of 18,000 photos".
/// Used above the results during a silent refresh and above the group list while the user reviews.
struct ScanProgressBar: View {
    let scan: ScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: scan.progress?.fractionCompleted ?? 0)
                .progressViewStyle(.linear)
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer(minLength: 8)
                    Text(scan.countText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    Text(scan.countText)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(titleKey, bundle: .module))
        .accessibilityValue(Text(scan.accessibilityProgressText))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var titleKey: LocalizedStringKey {
        scan.isPausedToCoolDown ? "scan.pausedToCoolDown" : "scan.scanning"
    }

    private var title: some View {
        Text(titleKey, bundle: .module)
    }
}

extension View {
    /// The rounded card every Home state is drawn in.
    func homeCard() -> some View {
        frame(maxWidth: .infinity)
            .padding(20)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

#if DEBUG
#Preview("Ring") {
    ProgressRing(fraction: 0.42, label: "42 %")
        .padding()
}

#Preview("Bar, dark, AX5") {
    let scan = ScanViewModel.preview()
    return ScanProgressBar(scan: scan)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
        .task { await scan.startScan() }
}
#endif

import Domain
import SwiftUI

/// Never scanned: what the app does and "Start Scan".
struct HomeIdleCard: View {
    let onStart: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var symbolSide: CGFloat = 72

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.on.square")
                .font(.title)
                .foregroundStyle(.background)
                .frame(width: symbolSide, height: symbolSide)
                .background(.primary, in: Circle())
                .accessibilityHidden(true)
            Text("home.idle.title", bundle: .module)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("home.idle.message", bundle: .module)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HomePrimaryButton(titleKey: "scan.start", hintKey: "scan.start.hint", action: onStart)
        }
        .homeCard()
    }
}

/// A scan the user started: progress ring, count, ETA, throttling notice, the live group counter with "Review Now",
/// and Cancel. Every row keeps its height while the scan runs (an empty ETA, notice or counter row stays reserved),
/// so the card never jumps. At 100 %, while the results are saved, the ring spins and says "Finishing…".
struct HomeScanningCard: View {
    let scan: ScanViewModel
    let foundSoFar: Int
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                ProgressRing(
                    fraction: scan.progress?.fractionCompleted ?? 0,
                    label: scan.percentText,
                    isFinishing: scan.isFinishing
                )
                Text(scan.isFinishing ? "scan.finishing" : "scan.scanning", bundle: .module)
                    .font(.headline)
                Text(scan.countText)
                    .font(.subheadline)
                    .monospacedDigit()
                Text(scan.etaText ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(scan.etaText == nil ? 0 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(scan.isFinishing ? "scan.finishing" : "scan.scanning", bundle: .module))
            .accessibilityValue(Text(scan.accessibilityProgressText))
            .accessibilityAddTraits(.updatesFrequently)

            notice
            Text("scan.groupsSoFar \(foundSoFar)", bundle: .module)
                .font(.headline)
                .monospacedDigit()
                .accessibilityAddTraits(.updatesFrequently)
            HomePrimaryButton(titleKey: "home.reviewNow", hintKey: "home.reviewNow.hint", action: onReview)
                .disabled(foundSoFar == 0)
            Button(role: .cancel) {
                scan.cancelScan()
            } label: {
                Text("scan.cancel", bundle: .module)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityHint(Text("scan.cancel.hint", bundle: .module))
        }
        .homeCard()
    }

    /// The cool-down or Low Power notice; its line stays reserved while there is none.
    @ViewBuilder private var notice: some View {
        if scan.isPausedToCoolDown {
            HomeNotice(key: "scan.pausedToCoolDown", systemImage: "thermometer.high")
        } else if scan.isSlowedByLowPowerMode {
            HomeNotice(key: "scan.lowPowerMode", systemImage: "battery.25percent")
        } else {
            HomeNotice(key: "scan.lowPowerMode", systemImage: "battery.25percent")
                .hidden()
                .accessibilityHidden(true)
        }
    }
}

/// Groups to review, in a few calm lines: what can be freed as a large figure, a storage-style bar of the photos in
/// groups (to delete / kept) with its legend, one summary line ("12 groups · 87 photos · 18,000 scanned", or the
/// silent refresh's progress in the same place), and Review. Placeholders keep every row's height while sizes load.
struct HomeResultsCard: View {
    let summary: HomeSummary
    /// Sizes of the photos in groups, once looked up.
    var sizes: GroupSizes?
    /// Photos the last scan went through.
    var scannedCount: Int?
    /// The silent refresh's progress line ("Checking for new photos… 42 %"), while it runs.
    var refreshText: String?
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            StorageBar(sizes: sizes)
            summaryLine
            HomePrimaryButton(titleKey: "home.review", hintKey: "home.review.hint", action: onReview)
        }
        .homeCard()
    }

    /// "214 MB" over "Can be freed"; a placeholder of the same size while it is estimated. VoiceOver reads the
    /// sentence ("About 214 MB can be freed").
    private var hero: some View {
        let size = summary.reclaimableSizeText
            ?? (summary.selectedPhotoCount == 0 ? Int64(0).formatted(.byteCount(style: .file)) : nil)
        return VStack(alignment: .leading, spacing: 2) {
            HomeHeroNumber(text: size ?? "000 MB")
                .redacted(reason: size == nil ? .placeholder : [])
            Text(summary.isLowerBound ? "home.reclaimable.caption.atLeast" : "home.reclaimable.caption",
                 bundle: .module)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary.reclaimableText ?? size ?? ""))
    }

    /// One line: the counts, or the refresh's progress while it runs (same height either way).
    private var summaryLine: some View {
        Group {
            if let refreshText {
                Label {
                    Text(refreshText)
                } icon: {
                    ProgressView()
                        .controlSize(.mini)
                }
            } else {
                Text(countsText)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .accessibilityAddTraits(refreshText == nil ? [] : .updatesFrequently)
    }

    /// "12 groups · 87 photos · 18,000 scanned".
    private var countsText: String {
        var parts = [
            String(localized: "home.summary.groups \(summary.groupCount)", bundle: .module),
            String(localized: "clusters.row.photos \(summary.photoCount)", bundle: .module)
        ]
        if let scannedCount, scannedCount > 0 {
            parts.append(String(localized: "home.summary.scanned \(scannedCount.formatted())", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }
}

/// The last scan found nothing: "No similar photos found" and "Scan Again".
struct HomeEmptyCard: View {
    let onScanAgain: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("scan.noGroups", bundle: .module)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("home.empty.message", bundle: .module)
                .foregroundStyle(.secondary)
            HomePrimaryButton(titleKey: "home.scanAgain", hintKey: "scan.start.hint", action: onScanAgain)
        }
        .multilineTextAlignment(.center)
        .homeCard()
    }
}

/// The last scan stopped with an error: the message, "Try Again", and "Review" if groups were found before it.
struct HomeErrorCard: View {
    let message: String
    let summary: HomeSummary
    let onRetry: () -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HomePrimaryButton(titleKey: "home.retry", hintKey: "scan.start.hint", action: onRetry)
            if summary.groupCount > 0 {
                Text("scan.groupsFound \(summary.groupCount)", bundle: .module)
                    .font(.headline)
                HomePrimaryButton(titleKey: "home.review", hintKey: "home.review.hint", action: onReview)
            }
        }
        .homeCard()
    }
}

/// "128 photos skipped (stored only in iCloud)", tappable for the explanation.
struct SkippedSummaryButton: View {
    let headline: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .accessibilityHidden(true)
                Text(headline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("home.skipped.hint", bundle: .module))
    }
}

/// The prominent full-width button of a card: an ink pill (`HomeInkButtonStyle`).
struct HomePrimaryButton: View {
    let titleKey: LocalizedStringKey
    let hintKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
        }
        .buttonStyle(HomeInkButtonStyle())
        .accessibilityHint(Text(hintKey, bundle: .module))
    }
}

/// A notice line with an orange icon, such as "Paused to cool down". The text stays `.primary`: orange text on
/// the card is about 2:1 in Light mode.
struct HomeNotice: View {
    let key: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(key, bundle: .module)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
    }
}

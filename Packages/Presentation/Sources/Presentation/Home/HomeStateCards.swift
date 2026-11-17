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

/// A scan the user started: progress ring, count, ETA, throttling notices, the live group counter with
/// "Review Now", and Cancel.
struct HomeScanningCard: View {
    let scan: ScanViewModel
    let foundSoFar: Int
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                ProgressRing(fraction: scan.progress?.fractionCompleted ?? 0, label: scan.percentText)
                Text("scan.scanning", bundle: .module)
                    .font(.headline)
                Text(scan.countText)
                    .font(.subheadline)
                    .monospacedDigit()
                if let eta = scan.etaText {
                    Text(eta)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("scan.scanning", bundle: .module))
            .accessibilityValue(Text(scan.accessibilityProgressText))
            .accessibilityAddTraits(.updatesFrequently)

            if scan.isPausedToCoolDown {
                HomeNotice(key: "scan.pausedToCoolDown", systemImage: "thermometer.high")
            } else if scan.isSlowedByLowPowerMode {
                HomeNotice(key: "scan.lowPowerMode", systemImage: "battery.25percent")
            }
            if foundSoFar > 0 {
                Text("scan.groupsSoFar \(foundSoFar)", bundle: .module)
                    .font(.headline)
                    .accessibilityAddTraits(.updatesFrequently)
                HomePrimaryButton(titleKey: "home.reviewNow", hintKey: "home.reviewNow.hint", action: onReview)
            }
            Button(role: .cancel) {
                scan.cancelScan()
            } label: {
                Text("scan.cancel", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("scan.cancel.hint", bundle: .module))
        }
        .homeCard()
    }
}

/// Groups to review. With a known size, the size selected for deletion leads as a large figure ("214 MB", "Can be
/// freed") above tiles with the group count, the photo count and the size of all photos in groups; otherwise "12
/// groups of similar photos found" and "38 photos in these groups". Then Review and Start Over.
struct HomeResultsCard: View {
    let summary: HomeSummary
    /// The size of all photos in groups ("1.4 GB"), once known.
    var totalSizeText: String?
    let onReview: () -> Void
    var onStartOver: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let size = summary.reclaimableSizeText {
                hero(size: size)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { stats }
                    VStack(spacing: 8) { stats }
                }
            } else {
                counts
                if let totalSizeText {
                    HomeStatTile(text: totalSizeText, titleKey: "home.stat.totalSize")
                }
            }
            HomePrimaryButton(titleKey: "home.review", hintKey: "home.review.hint", action: onReview)
            if let onStartOver {
                HomeStartOverButton(action: onStartOver)
            }
        }
        .homeCard()
    }

    /// The size as a large figure; VoiceOver reads the whole sentence ("About 214 MB can be freed").
    private func hero(size: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeHeroNumber(text: size)
            Text(summary.isLowerBound ? "home.reclaimable.caption.atLeast" : "home.reclaimable.caption",
                 bundle: .module)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary.reclaimableText ?? size))
    }

    @ViewBuilder private var stats: some View {
        HomeStatTile(value: summary.groupCount, titleKey: "home.stat.groups")
        HomeStatTile(value: summary.photoCount, titleKey: "home.stat.photos")
        if let totalSizeText {
            HomeStatTile(text: totalSizeText, titleKey: "home.stat.totalSize")
        }
    }

    /// The counts as sentences, while no size is known.
    private var counts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("scan.groupsFound \(summary.groupCount)", bundle: .module)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("home.photosInGroups \(summary.photoCount)", bundle: .module)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

import Domain
import SwiftUI

/// Never scanned: what the app does and "Start Scan".
struct HomeIdleCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.on.square")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("home.idle.title", bundle: .module)
                .font(.title2.bold())
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

/// Groups to review: "12 groups of similar photos found", "38 photos in these groups", "About 214 MB can be freed".
struct HomeResultsCard: View {
    let summary: HomeSummary
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("scan.groupsFound \(summary.groupCount)", bundle: .module)
                    .font(.title2.bold())
                Text("home.photosInGroups \(summary.photoCount)", bundle: .module)
                    .foregroundStyle(.secondary)
                if let reclaimable = summary.reclaimableText {
                    Text(reclaimable)
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            HomePrimaryButton(titleKey: "home.review", hintKey: "home.review.hint", action: onReview)
        }
        .homeCard()
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
                .font(.title2.bold())
            Text("home.empty.message", bundle: .module)
                .foregroundStyle(.secondary)
            Button(action: onScanAgain) {
                Text("home.scanAgain", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("scan.start.hint", bundle: .module))
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
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRetry) {
                Text("home.retry", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("scan.start.hint", bundle: .module))
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

/// The prominent full-width button of a card.
struct HomePrimaryButton: View {
    let titleKey: LocalizedStringKey
    let hintKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint(Text(hintKey, bundle: .module))
    }
}

/// An orange notice line with an icon, such as "Paused to cool down".
struct HomeNotice: View {
    let key: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(key, bundle: .module)
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
    }
}

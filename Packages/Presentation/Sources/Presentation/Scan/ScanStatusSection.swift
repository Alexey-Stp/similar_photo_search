import Domain
import SwiftUI

/// The scan controls on Home: Start Scan, then progress with ETA, throttling notices, the live group count and
/// Cancel. SPS-20 builds the full dashboard around it.
struct ScanStatusSection: View {
    let viewModel: ScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isScanning {
                scanning
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { viewModel.scanScreenAppeared() }
        .onDisappear { viewModel.scanScreenDisappeared() }
    }

    @ViewBuilder
    private var scanning: some View {
        ProgressView(value: viewModel.progress?.fractionCompleted ?? 0) {
            Text("scan.scanning", bundle: .module)
                .font(.headline)
        } currentValueLabel: {
            Text(viewModel.countText)
        }
        .accessibilityValue(Text(viewModel.percentText))

        if let eta = viewModel.etaText {
            Text(eta)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if viewModel.isPausedToCoolDown {
            notice("scan.pausedToCoolDown", systemImage: "thermometer.high")
        } else if viewModel.isSlowedByLowPowerMode {
            notice("scan.lowPowerMode", systemImage: "battery.25percent")
        }
        if viewModel.groupCount > 0 {
            Text("scan.groupsSoFar \(viewModel.groupCount)", bundle: .module)
                .font(.subheadline)
        }
        Button(role: .cancel) {
            viewModel.cancelScan()
        } label: {
            Text("scan.cancel", bundle: .module)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(Text("scan.cancel.hint", bundle: .module))
    }

    @ViewBuilder
    private var idle: some View {
        if let error = viewModel.errorText {
            Label {
                Text(error)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.red)
        } else if viewModel.progress?.phase == .done {
            Group {
                if viewModel.groupCount == 0 {
                    Text("scan.noGroups", bundle: .module)
                } else {
                    Text("scan.groupsFound \(viewModel.groupCount)", bundle: .module)
                }
            }
            .font(.headline)
        }
        Button {
            Task { await viewModel.startScan() }
        } label: {
            Text("scan.start", bundle: .module)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(Text("scan.start.hint", bundle: .module))
    }

    private func notice(_ key: LocalizedStringKey, systemImage: String) -> some View {
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

#if DEBUG
#Preview("Scanning") {
    let viewModel = ScanViewModel.preview()
    return ScanStatusSection(viewModel: viewModel)
        .padding()
        .task { await viewModel.startScan() }
}

#Preview("Paused, dark") {
    let viewModel = ScanViewModel.preview(snapshot: ScanProgress(
        processed: 800,
        total: 10_000,
        phase: .throttled,
        conditions: ScanConditions(thermalLevel: .critical)
    ))
    return ScanStatusSection(viewModel: viewModel)
        .padding()
        .preferredColorScheme(.dark)
        .task { await viewModel.startScan() }
}

#Preview("Idle") {
    ScanStatusSection(viewModel: .preview())
        .padding()
}
#endif

import Domain
import SwiftUI

/// The groups of similar photos, opened from Home ("Review", "Review now"). While a scan runs, a compact progress
/// bar stays at the top and new groups are appended at the end.
///
/// Interim rows (photo count, "Review recommended"); SPS-21 replaces them with thumbnail cards.
struct ClusterListScreen: View {
    let scan: ScanViewModel

    var body: some View {
        List(scan.selection.clusterIDs, id: \.self) { clusterID in
            if let state = scan.selection.state(for: clusterID) {
                ClusterSummaryRow(state: state)
            }
        }
        .navigationTitle(Text("clusters.title", bundle: .module))
        .safeAreaInset(edge: .top, spacing: 0) {
            if scan.isScanning {
                ScanProgressBar(scan: scan)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionSummaryBar(store: scan.selection)
        }
        .onAppear { scan.scanScreenAppeared() }
        .onDisappear { scan.scanScreenDisappeared() }
    }
}

/// One group: its photo count and how many are selected; reads only its own cluster's state.
private struct ClusterSummaryRow: View {
    let state: ClusterSelectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("clusters.row.photos \(state.memberIDs.count)", bundle: .module)
                .font(.headline)
            Text("clusters.row.selected \(state.selectedIDs.count)", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if state.needsReview {
                Label {
                    Text("selection.reviewRecommended", bundle: .module)
                } icon: {
                    Image(systemName: "eye")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Groups while scanning") {
    let scan = ScanViewModel.preview()
    return NavigationStack {
        ClusterListScreen(scan: scan)
    }
    .task { await scan.startScan() }
}

#Preview("Groups, dark") {
    NavigationStack {
        ClusterListScreen(scan: .preview())
    }
    .preferredColorScheme(.dark)
}
#endif

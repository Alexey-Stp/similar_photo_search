import SwiftUI

/// The groups found, listed on Home under the summary card: a header with "See All" (the group list with its
/// filters and the delete bar), then every group's card. Photos are toggled right here.
struct HomeGroupsSection: View {
    let list: ClusterListViewModel
    let onCompare: (String) -> Void
    let onSeeAll: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("home.groups.title", bundle: .module)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onSeeAll) {
                    Text("home.groups.seeAll", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityHint(Text("home.review.hint", bundle: .module))
            }
            LazyVStack(spacing: 16) {
                ForEach(list.rows, id: \.self) { clusterID in
                    ClusterCardRow(viewModel: list, clusterID: clusterID, onCompare: onCompare)
                }
            }
        }
        .onChange(of: list.scan.clusterRevision, initial: true) { list.clustersChanged() }
        .onChange(of: displayScale, initial: true) { list.displayScaleChanged(displayScale) }
    }
}

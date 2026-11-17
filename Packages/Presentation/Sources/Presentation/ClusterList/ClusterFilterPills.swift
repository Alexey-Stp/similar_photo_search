import SwiftUI

/// The filter as a row of pills above the groups: All Groups, Needs Review, Exact Duplicates. The chosen one is an
/// ink pill (label colour on the background colour); the row scrolls sideways when it doesn't fit.
struct ClusterFilterPills: View {
    @Bindable var viewModel: ClusterListViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(.all, key: "clusters.filter.all")
                pill(.needsReview, key: "clusters.filter.needsReview")
                pill(.exactDuplicates, key: "clusters.filter.exactDuplicates")
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("clusters.filter", bundle: .module))
    }

    private func pill(_ filter: ClusterListViewModel.Filter, key: LocalizedStringKey) -> some View {
        let isSelected = viewModel.filter == filter
        return Button {
            viewModel.filter = filter
        } label: {
            Text(key, bundle: .module)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.fill.tertiary), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

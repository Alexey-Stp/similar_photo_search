import SwiftUI

/// Builds the comparison's view model once per presentation (through the app's `ViewModelFactory`) and shows the
/// screen.
struct PhotoComparisonHost: View {
    let clusterID: String

    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: PhotoComparisonViewModel?

    var body: some View {
        Group {
            if let viewModel {
                PhotoComparisonScreen(viewModel: viewModel)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = factory?.makePhotoComparisonViewModel(clusterID: clusterID)
            }
        }
    }
}

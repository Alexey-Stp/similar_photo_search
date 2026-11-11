import Domain
import SwiftUI

/// Builds view models with their dependencies.
///
/// The app target's `AppContainer` conforms to this protocol and is injected with
/// `.environment(\.viewModelFactory, container)`, so Presentation never sees concrete Data types.
@MainActor
public protocol ViewModelFactory: AnyObject, Sendable {
    /// Creates the view model that owns photo access state and top-level routing.
    func makePermissionViewModel() -> PermissionViewModel

    /// Creates the view model for the "Scan scope" sheet.
    /// - Parameter onApply: Called after the chosen scope has been saved.
    func makeScopeSelectionViewModel(
        onApply: @escaping @MainActor (ScopePreferences) -> Void
    ) -> ScopeSelectionViewModel

    /// The keep / delete choice of the current app session (SPS-18). One instance for the whole session, so
    /// overrides survive a rescan.
    var selectionStore: SelectionStore { get }

    /// The scan of the current app session (SPS-14). One instance, so a running scan survives navigation.
    var scanViewModel: ScanViewModel { get }

    /// The home dashboard of the current app session (SPS-20). One instance, so the stored results are loaded and
    /// the launch scan is started once.
    var homeViewModel: HomeViewModel { get }

    /// The group list of the current app session (SPS-21). One instance, so filter, sort and the looked-up dates
    /// and sizes survive navigation.
    var clusterListViewModel: ClusterListViewModel { get }

    /// Creates the full-screen comparison of one group (SPS-22), over `clusterListViewModel`.
    func makePhotoComparisonViewModel(clusterID: String) -> PhotoComparisonViewModel

    /// Creates the deletion flow (review, progress, result) for one tap on "Delete N photos" (SPS-25).
    func makeDeletionViewModel(request: ClusterListViewModel.DeletionRequest) -> DeletionViewModel
}

private struct ViewModelFactoryKey: EnvironmentKey {
    static let defaultValue: (any ViewModelFactory)? = nil
}

extension EnvironmentValues {
    /// The factory used to build view models. Set once by the app's composition root.
    public var viewModelFactory: (any ViewModelFactory)? {
        get { self[ViewModelFactoryKey.self] }
        set { self[ViewModelFactoryKey.self] = newValue }
    }
}

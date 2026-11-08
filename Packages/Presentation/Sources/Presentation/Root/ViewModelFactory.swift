import SwiftUI

/// Builds view models with their dependencies.
///
/// The app target's `AppContainer` conforms to this protocol and is injected with
/// `.environment(\.viewModelFactory, container)`, so Presentation never sees concrete Data types.
@MainActor
public protocol ViewModelFactory: AnyObject, Sendable {
    /// Creates the view model of the root screen.
    func makeRootViewModel() -> RootViewModel
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

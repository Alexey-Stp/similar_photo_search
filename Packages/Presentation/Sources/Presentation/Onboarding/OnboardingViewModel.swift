import Domain
import Observation

/// Drives the three-page welcome flow.
///
/// The current page lives only in memory, so if the app is killed partway through,
/// onboarding starts again from the first page.
@Observable
@MainActor
public final class OnboardingViewModel {
    /// What the button on the last page does.
    public enum PrimaryAction: Sendable, Equatable {
        /// Photo access was never asked for: show the system prompt, then finish onboarding.
        case allowAccess
        /// Access was already decided (for example after a reinstall): finish without a prompt.
        case `continue`
    }

    /// The pages, in order.
    public let pages: [OnboardingPage]
    /// Index of the visible page. Bound to the paged `TabView`, so swiping updates it too.
    public var currentPage = 0
    /// Whether the last-page action is running. The button is disabled meanwhile.
    public private(set) var isWorking = false

    /// Whether the visible page is the permission primer.
    public var isLastPage: Bool {
        currentPage >= pages.count - 1
    }

    /// What the last-page button does, based on the current authorization status.
    public var primaryAction: PrimaryAction {
        switch permission.status {
        case nil, .notDetermined:
            .allowAccess
        case .authorized, .limited, .denied, .restricted:
            .continue
        }
    }

    private let permission: PermissionViewModel
    private let onComplete: @MainActor () -> Void

    /// Creates the view model.
    /// - Parameters:
    ///   - permission: Reads and requests photo library access.
    ///   - onComplete: Called once the user finishes onboarding; stores the completion flag.
    ///   - pages: The pages to show. Defaults to `OnboardingPage.all`.
    public init(
        permission: PermissionViewModel,
        onComplete: @escaping @MainActor () -> Void,
        pages: [OnboardingPage] = OnboardingPage.all
    ) {
        self.permission = permission
        self.onComplete = onComplete
        self.pages = pages
    }

    /// Moves to the next page. Does nothing on the last page.
    public func advance() {
        guard !isLastPage else { return }
        currentPage += 1
    }

    /// Runs the last-page action: asks for access if it was never asked for, then finishes
    /// onboarding. Repeated taps while it is running are ignored.
    public func performPrimaryAction() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if primaryAction == .allowAccess {
            await permission.requestAccess()
        }
        onComplete()
    }
}

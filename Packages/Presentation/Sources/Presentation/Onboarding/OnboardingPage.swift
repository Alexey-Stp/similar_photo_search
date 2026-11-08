/// One page of the first-launch welcome flow.
///
/// Text is stored as String Catalog keys and rendered with `Text(_:bundle: .module)`.
public struct OnboardingPage: Identifiable, Sendable, Equatable {
    /// Position of the page in the flow, starting at 0. Also used as the `TabView` selection tag.
    public let id: Int
    /// SF Symbol shown at the top of the page.
    public let symbol: String
    /// Optional second SF Symbol shown next to the main one.
    public let secondarySymbol: String?
    /// String Catalog key of the page title.
    public let titleKey: String
    /// String Catalog key of the page body.
    public let bodyKey: String

    /// The three onboarding pages, in order: what the app does, the on-device promise, and the
    /// permission primer.
    public static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            symbol: "photo.on.rectangle.angled",
            secondarySymbol: nil,
            titleKey: "onboarding.page1.title",
            bodyKey: "onboarding.page1.body"
        ),
        OnboardingPage(
            id: 1,
            symbol: "lock.shield",
            secondarySymbol: "airplane",
            titleKey: "onboarding.page2.title",
            bodyKey: "onboarding.page2.body"
        ),
        OnboardingPage(
            id: 2,
            symbol: "iphone",
            secondarySymbol: nil,
            titleKey: "onboarding.page3.title",
            bodyKey: "onboarding.page3.body"
        )
    ]
}

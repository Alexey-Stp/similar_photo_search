import SwiftUI

/// First-launch welcome flow: what the app does, the on-device promise, and the photo access primer.
///
/// The last page's button asks for photo access if it was never asked for, then calls `onComplete`.
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: OnboardingViewModel

    /// Creates the view.
    /// - Parameters:
    ///   - permission: Reads and requests photo library access.
    ///   - onComplete: Called once the user finishes onboarding.
    init(permission: PermissionViewModel, onComplete: @escaping @MainActor () -> Void) {
        _model = State(initialValue: OnboardingViewModel(permission: permission, onComplete: onComplete))
    }

    var body: some View {
        VStack(spacing: 0) {
            pager
            actionBar
        }
    }

    private var pager: some View {
        TabView(selection: $model.currentPage) {
            ForEach(model.pages) { page in
                OnboardingPageView(page: page)
                    .tag(page.id)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        #endif
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
    }

    private var actionBar: some View {
        Group {
            if model.isLastPage {
                Button {
                    Task { await model.performPrimaryAction() }
                } label: {
                    primaryLabel
                        .frame(maxWidth: .infinity)
                }
                .accessibilityHint(primaryHint)
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        model.advance()
                    }
                } label: {
                    Text("onboarding.next", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityHint(Text("onboarding.next.hint", bundle: .module))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isWorking)
        .padding()
    }

    private var primaryLabel: Text {
        switch model.primaryAction {
        case .allowAccess:
            Text("onboarding.allowAccess", bundle: .module)
        case .continue:
            Text("onboarding.continue", bundle: .module)
        }
    }

    private var primaryHint: Text {
        switch model.primaryAction {
        case .allowAccess:
            Text("onboarding.allowAccess.hint", bundle: .module)
        case .continue:
            Text("onboarding.continue.hint", bundle: .module)
        }
    }
}

/// One onboarding page. Scrolls, so long localized text at accessibility sizes is never clipped.
private struct OnboardingPageView: View {
    let page: OnboardingPage
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                symbols
                Text(LocalizedStringKey(page.titleKey), bundle: .module)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(page.bodyKey), bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            // Leave room for the page dots.
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private var symbols: some View {
        HStack(spacing: 16) {
            Image(systemName: page.symbol)
            if let secondary = page.secondarySymbol {
                Image(systemName: secondary)
            }
        }
        // Grow with Dynamic Type, but cap it so the text still fits at AX sizes.
        .font(.system(size: min(symbolSize, 96)))
        .foregroundStyle(.tint)
        .padding(.top, 32)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Light") {
    OnboardingView(permission: .preview(status: .notDetermined)) {}
}

#Preview("Dark") {
    OnboardingView(permission: .preview(status: .notDetermined)) {}
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    OnboardingView(permission: .preview(status: .notDetermined)) {}
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Already granted") {
    let permission = PermissionViewModel.preview(status: .authorized)
    return OnboardingView(permission: permission) {}
        .task { await permission.refresh() }
}
#endif

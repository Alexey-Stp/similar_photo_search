import SwiftUI

/// First-launch screen. Placeholder content until the onboarding ticket.
struct OnboardingView: View {
    let viewModel: PermissionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(.largeTitle))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("onboarding.title", bundle: .module)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("onboarding.message", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.requestAccess() }
                } label: {
                    Text("onboarding.continue", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(Text("onboarding.continue.hint", bundle: .module))
            }
            .padding()
        }
    }
}

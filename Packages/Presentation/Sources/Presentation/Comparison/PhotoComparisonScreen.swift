import Domain
import SwiftUI

/// Full-screen comparison of one group (SPS-22): a pager across the photos (or two photos side by side on iPad and
/// in landscape, zooming together), the filmstrip, and the info panel with the actions. Swipe down or Close to
/// dismiss; every choice is already in `SelectionStore`.
struct PhotoComparisonScreen: View {
    @Bindable var viewModel: PhotoComparisonViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissOffset: CGFloat = 0

    /// Distance or predicted distance of a downward swipe that dismisses the screen.
    private static let dismissDistance: CGFloat = 120

    /// Top bar, photos, filmstrip and info panel on black.
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ComparisonTopBar(viewModel: viewModel) { dismiss() }
                if viewModel.isAvailable {
                    photos
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .simultaneousGesture(dismissDrag)
                    ComparisonFilmstrip(viewModel: viewModel)
                    if let focused = viewModel.focusedID {
                        ScrollView {
                            ComparisonInfoPanel(viewModel: viewModel, assetID: focused)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxHeight: proxy.size.height * 0.4)
                    }
                } else {
                    groupGone
                }
            }
            .offset(y: dismissOffset)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .statusBarHidden()
        .accessibilityAction(.escape) { dismiss() }
        .confirmationDialog(
            Text("clusters.deleteAll.title", bundle: .module),
            isPresented: $viewModel.isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                viewModel.confirmDeleteAll()
            } label: {
                Text("clusters.deleteAll.confirm", bundle: .module)
            }
        } message: {
            Text("clusters.deleteAll.message", bundle: .module)
        }
        .onChange(of: canShowSideBySide, initial: true) { _, canShow in
            viewModel.layoutChanged(canShowSideBySide: canShow)
        }
        .task(id: viewModel.memberIDs) { await viewModel.loadDetails() }
    }

    private var canShowSideBySide: Bool {
        ComparisonLayout.canShowSideBySide(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    @ViewBuilder private var photos: some View {
        if viewModel.showsSideBySide, let left = viewModel.shownCurrentID, let right = viewModel.shownSecondaryID {
            HStack(spacing: 2) {
                sidePane(left, pane: .primary)
                sidePane(right, pane: .secondary)
            }
        } else {
            TabView(selection: currentBinding) {
                ForEach(viewModel.memberIDs, id: \.self) { assetID in
                    ComparisonPagerPage(viewModel: viewModel, assetID: assetID)
                        .tag(assetID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    /// One pane of the side-by-side mode; both share `sharedZoom`. Tapping it focuses it.
    private func sidePane(_ assetID: String, pane: PhotoComparisonViewModel.Pane) -> some View {
        let isFocused = viewModel.focusedPane == pane
        return ComparisonPane(
            assetID: assetID,
            isActive: true,
            isMissing: viewModel.isMissing(assetID),
            loader: viewModel.screenImageLoader,
            zoom: viewModel.sharedZoom,
            accessibilityLabel: viewModel.accessibilityLabel(for: assetID)
        )
        .overlay {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: isFocused ? 3 : 0)
                .allowsHitTesting(false)
        }
        .simultaneousGesture(TapGesture().onEnded { viewModel.focus(pane) })
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction(named: Text("compare.action.focus", bundle: .module)) { viewModel.focus(pane) }
    }

    private var currentBinding: Binding<String> {
        Binding(
            get: { viewModel.shownCurrentID ?? "" },
            set: { viewModel.currentID = $0 }
        )
    }

    private var groupGone: some View {
        VStack {
            Spacer()
            Text("compare.groupGone", bundle: .module)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Swipe down to dismiss, only while the photo is not zoomed (then a drag pans) and the swipe is mostly vertical.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !viewModel.activeZoom.isZoomed,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = dismissOffset > Self.dismissDistance
                    || (dismissOffset > 0 && value.predictedEndTranslation.height > Self.dismissDistance * 2.5)
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { dismissOffset = 0 }
                }
            }
    }
}

/// One page of the pager. Only the current page uses `pagerZoom`; the others sit at 1× and hold an image only
/// while they are next to the current page.
private struct ComparisonPagerPage: View {
    let viewModel: PhotoComparisonViewModel
    let assetID: String
    @State private var idleZoom = ZoomState()

    var body: some View {
        let isCurrent = viewModel.shownCurrentID == assetID
        ComparisonPane(
            assetID: assetID,
            isActive: viewModel.shouldLoadFullImage(assetID),
            isMissing: viewModel.isMissing(assetID),
            loader: viewModel.screenImageLoader,
            zoom: isCurrent ? viewModel.pagerZoom : idleZoom,
            accessibilityLabel: viewModel.accessibilityLabel(for: assetID)
        )
    }
}

/// Close, the position ("2 of 5") and the side-by-side switch.
private struct ComparisonTopBar: View {
    @Bindable var viewModel: PhotoComparisonViewModel
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("compare.close", bundle: .module))
            Spacer()
            if let focused = viewModel.focusedID, let position = viewModel.positionText(of: focused) {
                Text(position)
                    .font(.headline)
                    .monospacedDigit()
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if viewModel.canShowSideBySide, viewModel.memberIDs.count > 1 {
                Toggle(isOn: $viewModel.prefersSideBySide) {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .toggleStyle(.button)
                .accessibilityLabel(Text("compare.sideBySide", bundle: .module))
            } else {
                Color.clear.frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .foregroundStyle(.white)
    }
}

import Domain
import SwiftUI

/// Sheet for choosing what a scan covers: All Photos or albums, a date range, whether to skip screenshots,
/// and how far apart shots may be to still be compared (the session gap).
struct ScopeSelectionView: View {
    let viewModel: ScopeSelectionViewModel
    let onCancel: () -> Void

    /// The sheet: album list, date filter and screenshot toggle, with Cancel and Apply in the toolbar.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("scope.title", bundle: .module))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) {
                            Text("scope.cancel", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await viewModel.apply() }
                        } label: {
                            Text("scope.apply", bundle: .module)
                        }
                        .disabled(!viewModel.isLoaded)
                        .accessibilityHint(Text("scope.apply.hint", bundle: .module))
                    }
                }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.cancelPendingCount() }
    }

    /// A spinner until the saved choice and the albums are loaded, then the form.
    @ViewBuilder private var content: some View {
        if viewModel.isLoaded {
            form
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// All sections of the sheet.
    private var form: some View {
        List {
            Section {
                selectableRow(
                    title: Text("scope.allPhotos", bundle: .module),
                    count: nil,
                    isSelected: viewModel.isAllPhotos,
                    action: { viewModel.selectAllPhotos() }
                )
            } header: {
                Text("scope.section.library", bundle: .module)
            }
            if !viewModel.smartAlbums.isEmpty {
                Section {
                    ForEach(viewModel.smartAlbums) { albumRow($0) }
                } header: {
                    Text("scope.section.smartAlbums", bundle: .module)
                }
            }
            if !viewModel.userAlbums.isEmpty {
                Section {
                    ForEach(viewModel.userAlbums) { albumRow($0) }
                } header: {
                    Text("scope.section.myAlbums", bundle: .module)
                }
            }
            dateSection
            sessionGapSection
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.excludeScreenshots },
                    set: { viewModel.setExcludeScreenshots($0) }
                )) {
                    Text("scope.skipScreenshots", bundle: .module)
                }
            } footer: {
                countFooter
            }
        }
    }

    /// The date preset picker and, for Custom, the first and last day.
    private var dateSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.datePreset },
                set: { viewModel.setDatePreset($0) }
            )) {
                ForEach(ScopeSelectionViewModel.DatePreset.allCases) { preset in
                    presetTitle(preset).tag(preset)
                }
            } label: {
                Text("scope.date.label", bundle: .module)
            }
            if viewModel.datePreset == .custom {
                DatePicker(
                    selection: Binding(get: { viewModel.customStart }, set: { viewModel.setCustomStart($0) }),
                    in: ...Date(),
                    displayedComponents: .date
                ) {
                    Text("scope.date.from", bundle: .module)
                }
                DatePicker(
                    selection: Binding(get: { viewModel.customEnd }, set: { viewModel.setCustomEnd($0) }),
                    in: viewModel.customStart...,
                    displayedComponents: .date
                ) {
                    Text("scope.date.to", bundle: .module)
                }
            }
        } header: {
            Text("scope.section.dates", bundle: .module)
        }
    }

    /// The session gap picker: Strict 5 min, Balanced 15 min, Relaxed 60 min.
    private var sessionGapSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.sessionGap },
                set: { viewModel.setSessionGap($0) }
            )) {
                ForEach(SessionGapPreset.allCases) { gap in
                    sessionGapTitle(gap).tag(gap)
                }
            } label: {
                Text("scope.sessionGap.label", bundle: .module)
            }
            .accessibilityHint(Text("scope.sessionGap.hint", bundle: .module))
        } header: {
            Text("scope.section.grouping", bundle: .module)
        } footer: {
            Text("scope.sessionGap.footer", bundle: .module)
        }
    }

    /// "About N photos", with a spinner while a new count runs.
    private var countFooter: some View {
        HStack(spacing: 6) {
            if let count = viewModel.estimatedCount {
                Text("scope.footer.count \(count)", bundle: .module)
            }
            if viewModel.isCounting {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(Text("scope.footer.counting", bundle: .module))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A selectable row for one album, with its estimated count.
    private func albumRow(_ album: AlbumSummary) -> some View {
        selectableRow(
            title: albumTitle(album),
            count: album.estimatedCount,
            isSelected: viewModel.isSelected(album.id),
            action: { viewModel.toggle(album.id) }
        )
    }

    /// A row with a title, an optional photo count and a checkmark when selected.
    private func selectableRow(
        title: Text,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let count {
                        Text("scope.album.count \(count)", bundle: .module)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("scope.album.hint", bundle: .module))
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    /// The album's own title, or a localized name for its kind when PhotoKit gives none.
    private func albumTitle(_ album: AlbumSummary) -> Text {
        guard album.title.isEmpty else {
            return Text(verbatim: album.title)
        }
        switch album.kind {
        case .favorites:
            return Text("scope.album.favorites", bundle: .module)
        case .recents:
            return Text("scope.allPhotos", bundle: .module)
        case .selfies:
            return Text("scope.album.selfies", bundle: .module)
        case .portrait:
            return Text("scope.album.portrait", bundle: .module)
        case .user:
            return Text("scope.album.untitled", bundle: .module)
        }
    }

    /// The localized name of a session gap choice, including its length.
    private func sessionGapTitle(_ gap: SessionGapPreset) -> Text {
        switch gap {
        case .strict:
            Text("scope.sessionGap.strict", bundle: .module)
        case .balanced:
            Text("scope.sessionGap.balanced", bundle: .module)
        case .relaxed:
            Text("scope.sessionGap.relaxed", bundle: .module)
        }
    }

    /// The localized name of a date preset.
    private func presetTitle(_ preset: ScopeSelectionViewModel.DatePreset) -> Text {
        switch preset {
        case .anyTime:
            Text("scope.date.anyTime", bundle: .module)
        case .last30Days:
            Text("scope.date.last30Days", bundle: .module)
        case .thisYear:
            Text("scope.date.thisYear", bundle: .module)
        case .custom:
            Text("scope.date.custom", bundle: .module)
        }
    }
}

/// Builds the scope view model from the injected factory and shows the sheet.
/// A new view model is made every time the sheet opens, so albums deleted meanwhile drop out of the selection.
struct ScopeSelectionSheet: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: ScopeSelectionViewModel?
    let onDismiss: () -> Void

    /// The sheet once the view model exists, a spinner before that.
    var body: some View {
        Group {
            if let viewModel {
                ScopeSelectionView(viewModel: viewModel, onCancel: onDismiss)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil, let factory {
                viewModel = factory.makeScopeSelectionViewModel { _ in onDismiss() }
            }
        }
    }
}

#if DEBUG
#Preview("Light") {
    ScopeSelectionView(viewModel: .preview(), onCancel: {})
}

#Preview("Dark") {
    ScopeSelectionView(viewModel: .preview(), onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScopeSelectionView(viewModel: .preview(), onCancel: {})
        .dynamicTypeSize(.accessibility5)
}
#endif

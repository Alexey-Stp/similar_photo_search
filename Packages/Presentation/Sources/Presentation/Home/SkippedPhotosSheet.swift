import Domain
import SwiftUI

/// Why photos were left out of the scan, per reason, with what the user can do about it. Explains that the app
/// never downloads iCloud originals because it never uses the network.
struct SkippedPhotosSheet: View {
    let summary: SkippedPhotosSummary
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(summary.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Self.titleKey(row.reason), bundle: .module)
                                    .font(.headline)
                                Spacer(minLength: 8)
                                Text(row.count.formatted())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(Self.detailKey(row.reason), bundle: .module)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("skipped.footer", bundle: .module)
                }
            }
            .navigationTitle(Text("skipped.title", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onDone) {
                        Text("skipped.done", bundle: .module)
                    }
                }
            }
        }
    }

    static func titleKey(_ reason: SkipReason) -> LocalizedStringKey {
        switch reason {
        case .iCloudOnly: "skipped.iCloudOnly.title"
        case .decodeFailed: "skipped.decodeFailed.title"
        case .notFound: "skipped.notFound.title"
        case .noDate: "skipped.noDate.title"
        }
    }

    static func detailKey(_ reason: SkipReason) -> LocalizedStringKey {
        switch reason {
        case .iCloudOnly: "skipped.iCloudOnly.detail"
        case .decodeFailed: "skipped.decodeFailed.detail"
        case .notFound: "skipped.notFound.detail"
        case .noDate: "skipped.noDate.detail"
        }
    }
}

#if DEBUG
#Preview("Skipped") {
    SkippedPhotosSheet(
        summary: SkippedPhotosSummary(counts: [.iCloudOnly: 128, .noDate: 3, .decodeFailed: 1]),
        onDone: {}
    )
}

#Preview("Skipped, dark, AX5") {
    SkippedPhotosSheet(summary: SkippedPhotosSummary(counts: [.iCloudOnly: 128]), onDone: {})
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
#endif

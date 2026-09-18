import SwiftUI

enum MidokuEmptyStateKind: String, CaseIterable, Identifiable {
    case home, library, search, history, downloads, offline
    var id: String { rawValue }

    var imageName: String {
        switch self {
        case .home: "MidokuEmptyHome"
        case .library: "MidokuEmptyLibrary"
        case .search: "MidokuEmptySearch"
        case .history: "MidokuEmptyHistory"
        case .downloads: "MidokuEmptyDownloads"
        case .offline: "MidokuEmptyOffline"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Make yourself at home"
        case .library: "Your library starts here"
        case .search: "No titles found"
        case .history: "Your next chapter awaits"
        case .downloads: "Take a story with you"
        case .offline: "You're offline"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .home: "Your reading and pinned source feeds will appear here."
        case .library: "Your saved manga will appear here."
        case .search: "Try a different title or adjust your filters."
        case .history: "Chapters you open will appear here."
        case .downloads: "Download chapters to read without a connection."
        case .offline: "Downloaded chapters are still available."
        }
    }

    var actionTitle: LocalizedStringKey? {
        switch self {
        case .home, .library: "Browse sources"
        case .offline: "Open downloads"
        case .search, .history, .downloads: nil
        }
    }
}

struct MidokuEmptyStateView: View {
    let kind: MidokuEmptyStateKind
    var action: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(kind.imageName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 192, maxHeight: 160)
                    .accessibilityHidden(true)

                Text(kind.title)
                    .font(.title3.bold())
                    .foregroundStyle(MidokuTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(kind.message)
                    .font(.body)
                    .foregroundStyle(MidokuTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let action, let actionTitle = kind.actionTitle {
                    Button(action: action) { Text(actionTitle) }
                        .buttonStyle(MidokuPrimaryButtonStyle())
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .background(MidokuTheme.background)
    }
}

#Preview("Empty Library") {
    MidokuEmptyStateView(kind: .library, action: {})
}

import SwiftUI

/// An AI-filtered important inbox — not a Gmail mirror. Messages are grouped by
/// what they demand of the user.
struct InboxView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            Group {
                switch app.inbox.state {
                case .disconnected:
                    InfoStateView(
                        systemImage: "envelope",
                        title: "Gmail not connected",
                        message: "Connect Gmail to see messages that need your attention.",
                        actionTitle: "Connect Gmail"
                    ) { Task { await app.connectGmail() } }
                case .loading, .idle:
                    LoadingStateView(message: "Loading your inbox…")
                case .empty:
                    InfoStateView(systemImage: "tray", title: "No important messages",
                                  message: "When something needs you, it'll show up here.")
                case let .failed(message):
                    InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load inbox",
                                  message: message, actionTitle: "Retry") { Task { await app.inbox.refresh() } }
                case let .loaded(messages):
                    inboxList(messages)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .task { await app.inbox.refresh() }
            .refreshable { await app.inbox.refresh() }
        }
    }

    private func inboxList(_ messages: [InboxMessage]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                ForEach(InboxSection.allCases) { section in
                    let items = messages.filter { $0.section == section }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            SectionHeader(title: section.rawValue)
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                                    InboxRow(message: message)
                                    if index < items.count - 1 { Divider().overlay(AppTheme.separator) }
                                }
                            }
                            .cardSurface(padding: 0)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
    }
}

#Preview {
    InboxView().environmentObject(PreviewSupport.appState())
}

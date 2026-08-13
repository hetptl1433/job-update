import SwiftUI

/// An AI-filtered important inbox — not a Gmail mirror. Messages are grouped by
/// what they demand of the user.
struct InboxView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @State private var filter: EmailAccountFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                switch inbox.state {
                case .disconnected:
                    VStack(spacing: AppTheme.Spacing.md) {
                        InfoStateView(systemImage: "envelope", title: "Email not connected",
                                      message: "Connect Gmail or Outlook to see messages that need your attention.")
                        Button("Connect Gmail") { Task { await app.connectGmailAccount() } }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Connect Outlook") { Task { await app.connectOutlookAccount() } }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    }
                    .padding(AppTheme.Spacing.xl)
                case .loading, .idle:
                    LoadingStateView(message: "Loading your inbox…")
                case .empty:
                    InfoStateView(systemImage: "tray", title: "No important messages",
                                  message: "When something needs you, it'll show up here.")
                case let .failed(message):
                    InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load inbox",
                                  message: message, actionTitle: "Retry") { Task { await app.syncEmail() } }
                case let .loaded(messages):
                    inboxList(messages)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) {
                if inbox.state.value != nil {
                    Picker("Account", selection: $filter) {
                        ForEach(EmailAccountFilter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await app.syncEmail() } } label: {
                        if app.isSyncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .tint(AppTheme.brand)
                    .disabled(app.isSyncing)
                }
            }
            .refreshable { await app.refreshInbox() }
            .task { await app.loadInboxIfNeeded() }
            .onChange(of: inbox.needsInitialLoad) { _, needsLoad in
                if needsLoad { Task { await app.loadInboxIfNeeded() } }
            }
        }
    }

    private func inboxList(_ messages: [InboxMessage]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                if let message = inbox.refreshError {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(AppTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Showing your saved inbox")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Button("Retry") { Task { await app.syncEmail() } }
                            .font(.caption.weight(.semibold))
                    }
                    .cardSurface(padding: AppTheme.Spacing.md)
                } else if app.isSyncing {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(app.syncStageMessage ?? "Refreshing your inbox…")
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                } else if let snapshotDate = inbox.snapshotDate {
                    Label(
                        "Updated \(snapshotDate.formatted(.relative(presentation: .named)))",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }

                ForEach(InboxSection.allCases) { section in
                    let items = messages.filter { $0.section == section && filter.includes($0.provider) }
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
    let app = PreviewSupport.appState()
    return InboxView().environmentObject(app).environmentObject(app.inbox)
}

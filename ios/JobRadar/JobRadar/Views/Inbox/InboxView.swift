import SwiftUI

/// An AI-filtered important inbox — not a Gmail mirror. Messages are grouped by
/// what they demand of the user.
struct InboxView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @EnvironmentObject private var tasks: TaskRepository
    @State private var filter: EmailAccountFilter = .all
    @State private var selectedMessage: InboxMessage?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    OrbitPageHeading(
                        title: "Inbox",
                        subtitle: "The important things find their way.",
                        actionTitle: "Refresh inbox",
                        symbol: "arrow.clockwise",
                        action: { Task { await app.syncEmail() } }
                    )

                    if inbox.state.value != nil {
                        Picker("Account", selection: $filter) {
                            ForEach(EmailAccountFilter.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

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
                            .cardSurface()
                        case .loading, .idle:
                            LoadingStateView(message: "Loading your inbox…").cardSurface()
                        case .empty:
                            InfoStateView(systemImage: "tray", title: "No important messages",
                                          message: "When something needs you, it'll show up here.").cardSurface()
                        case let .failed(message):
                            InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load inbox",
                                          message: message, actionTitle: "Retry") { Task { await app.syncEmail() } }
                                .cardSurface()
                        case let .loaded(messages):
                            inboxList(messages)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.background)
            .orbitNavigationChrome()
            .refreshable { await app.refreshInbox() }
            .inboxMessageDetail($selectedMessage)
            .task { await app.loadInboxIfNeeded() }
            .onChange(of: inbox.needsInitialLoad) { _, needsLoad in
                if needsLoad { Task { await app.loadInboxIfNeeded() } }
            }
        }
    }

    private func inboxList(_ messages: [InboxMessage]) -> some View {
        OrbitColumns {
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
                                    InboxMessageButton(
                                        message: message,
                                        isInToDo: tasks.tasks.contains { $0.relatedEmailID == message.id }
                                    ) { selectedMessage = message }
                                    if index < items.count - 1 { Divider().overlay(AppTheme.separator) }
                                }
                            }
                            .cardSurface(padding: 0)
                        }
                        .orbitColumn(.shorter)
                    }
                }
        }
    }
}

// MARK: - Message detail

/// An Inbox row that opens the message's detail, with quick actions on
/// touch and hold. Shared by Inbox and Home.
struct InboxMessageButton: View {
    @EnvironmentObject private var app: AppState
    let message: InboxMessage
    var isInToDo = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            InboxRow(message: message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardRowPreviewSurface()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { app.addEmailToTasks(message) } label: {
                Label(isInToDo ? "In your To Do" : "Add to To Do", systemImage: isInToDo ? "checkmark.circle" : "plus.circle")
            }
            .disabled(isInToDo)
            if !message.senderEmail.isEmpty {
                Button { UIPasteboard.general.string = message.senderEmail } label: {
                    Label("Copy sender address", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityHint("Opens the summary and actions")
    }
}

extension View {
    /// Presents an Inbox message's detail. Asking Orbit about it opens Chat
    /// once the detail has finished closing, so the two sheets never overlap.
    func inboxMessageDetail(_ message: Binding<InboxMessage?>) -> some View {
        modifier(InboxMessageDetailPresenter(message: message))
    }
}

private struct InboxMessageDetailPresenter: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Binding var message: InboxMessage?
    @State private var pendingChatPrompt: String?

    func body(content: Content) -> some View {
        content.sheet(item: $message, onDismiss: openPendingChat) { message in
            InboxMessageDetailView(message: message) { prompt in
                pendingChatPrompt = prompt
                self.message = nil
            }
        }
    }

    private func openPendingChat() {
        guard let prompt = pendingChatPrompt else { return }
        pendingChatPrompt = nil
        app.openAssistant(prompt: prompt)
    }
}

struct InboxMessageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    let message: InboxMessage
    let onAskOrbit: (String) -> Void
    @State private var copiedSender = false
    @State private var addedFeedback = 0

    private var linkedTask: TaskItem? {
        tasks.tasks.first { $0.relatedEmailID == message.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    header
                    summary
                    actions
                    source
                    Text("Orbit only reads your mail. It never replies, archives, or changes anything in your mailbox.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.background)
            .navigationTitle(message.section.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
        .sensoryFeedback(.success, trigger: addedFeedback)
        .task(id: copiedSender) {
            guard copiedSender else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedSender = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                OrbitAvatar(name: message.sender, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.sender)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    if !message.senderName.isEmpty, !message.senderEmail.isEmpty {
                        Text(message.senderEmail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(message.receivedAt.relativeShort)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                .font(.title3.weight(.semibold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            if message.actionRequired || message.importance == .high {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if message.actionRequired {
                        Tag(text: "Action required", systemImage: "bolt", tint: AppTheme.coral)
                    }
                    if message.importance == .high {
                        Tag(text: "Important", systemImage: "exclamationmark", tint: AppTheme.warning)
                    }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Orbit summary", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.coral)
            Text(message.aiSummary.isEmpty ? "No summary was saved for this message." : message.aiSummary)
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitFocusSurface(padding: AppTheme.Spacing.lg)
    }

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let linkedTask {
                Label(
                    linkedTask.isCompleted ? "Done in your To Do" : "In your To Do",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.success)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppTheme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            } else {
                Button {
                    app.addEmailToTasks(message)
                    addedFeedback += 1
                } label: {
                    Label("Add to To Do", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Button { onAskOrbit(chatPrompt) } label: {
                    Label("Ask Orbit", systemImage: "sparkles")
                        .frame(minHeight: 24)
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))

                if !message.senderEmail.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.senderEmail
                        copiedSender = true
                    } label: {
                        Label(copiedSender ? "Copied" : "Copy address", systemImage: copiedSender ? "checkmark" : "doc.on.doc")
                            .frame(minHeight: 24)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
        }
    }

    private var source: some View {
        VStack(spacing: 0) {
            detailRow("Mailbox", value: message.mailboxEmail, symbol: message.provider.systemImage)
            Divider().overlay(AppTheme.separator)
            detailRow("Account", value: message.provider.label, symbol: "person.crop.circle")
            Divider().overlay(AppTheme.separator)
            detailRow(
                "Received",
                value: message.receivedAt.formatted(date: .abbreviated, time: .shortened),
                symbol: "clock"
            )
        }
        .cardSurface(padding: 0)
    }

    private func detailRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: AppTheme.Spacing.md)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var chatPrompt: String {
        var prompt = "Help me handle this email from \(message.sender)"
        if !message.subject.isEmpty { prompt += " with the subject “\(message.subject)”" }
        prompt += "."
        if !message.aiSummary.isEmpty { prompt += " Summary: \(message.aiSummary)" }
        return prompt + " What should I do next?"
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return InboxView().environmentObject(app).environmentObject(app.inbox).environmentObject(app.tasks)
}

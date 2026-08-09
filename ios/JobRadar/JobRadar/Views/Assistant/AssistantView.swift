import SwiftData
import SwiftUI

/// A personal-data assistant. It reasons over the user's jobs, inbox, calendar
/// and connections via the connected ChatGPT (OpenAI) — not a generic chatbot.
/// The request is a prompt plus a compact, structured context; the app holds no
/// key in code (the user's key lives in the Keychain).
struct AssistantView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: GmailRepository
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var messages: [ChatMessage] = []
    @State private var input: String
    @State private var sending = false
    @State private var showConnect = false

    private let suggestions = [
        "Did any recruiter contact me today?",
        "Which companies haven't responded?",
        "Who should I follow up with?",
        "What interviews do I have this week?",
        "Summarize my day."
    ]

    init(initialPrompt: String = "") {
        _input = State(initialValue: initialPrompt)
    }

    var body: some View {
        Group {
            if app.connections.aiConnected {
                VStack(spacing: 0) {
                    if messages.isEmpty { emptyState } else { conversation }
                    inputBar
                }
            } else {
                connectPrompt
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConnect) { ConnectChatGPTView().environmentObject(app) }
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        InfoStateView(
            systemImage: "sparkles",
            title: "Connect ChatGPT",
            message: "The assistant answers using your jobs, inbox and calendar. Connect ChatGPT with your OpenAI key to enable it.",
            actionTitle: "Connect ChatGPT"
        ) { showConnect = true }
        .padding(AppTheme.Spacing.lg)
    }

    // MARK: Connected — empty

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "sparkles").font(.title).foregroundStyle(AppTheme.primaryText)
                    Text("Ask about your world")
                        .font(.title2.weight(.bold)).foregroundStyle(AppTheme.primaryText)
                    Text("I answer using your jobs, inbox and calendar — not the whole internet.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.top, AppTheme.Spacing.xl)

                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            input = suggestion
                            send()
                        } label: {
                            HStack {
                                Text(suggestion).font(.subheadline).foregroundStyle(AppTheme.primaryText)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(AppTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    ForEach(messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if sending {
                        HStack { ProgressView(); Spacer() }.padding(.horizontal, AppTheme.Spacing.lg)
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TextField("Ask anything…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .tint(AppTheme.accent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(AppTheme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: Context + send

    private var context: AssistantContext {
        var lines: [String] = []
        lines.append("Connections: \(app.gmailAccounts.count) Gmail mailbox(es), Calendar \(app.connections.calendarConnected ? "connected" : "not connected"), Health \(app.connections.healthConnected ? "connected" : "not connected").")

        if !jobs.isEmpty {
            lines.append("Job applications (\(jobs.count) total):")
            for job in jobs.prefix(25) {
                let role = job.position.isEmpty ? "?" : job.position
                let next = job.nextAction.isEmpty ? "" : "; next: \(job.nextAction)"
                lines.append("- \(job.company) — \(role) [\(job.status.rawValue)]\(next)")
            }
        }

        if case let .loaded(msgs) = inbox.state, !msgs.isEmpty {
            lines.append("Recent important emails:")
            for message in msgs.prefix(10) {
                lines.append("- \(message.sender): \(message.subject) — \(message.aiSummary)\(message.actionRequired ? " [action required]" : "")")
            }
        }

        return AssistantContext(userName: app.user?.firstName ?? "the user", lines: lines)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        messages.append(ChatMessage(role: .user, text: text))
        input = ""
        sending = true
        let ctx = context
        Task {
            do {
                let reply = try await app.assistant.answer(text, context: ctx)
                messages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                messages.append(ChatMessage(role: .assistant, text: "I couldn't get a response: \(error.localizedDescription)"))
            }
            sending = false
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? AppTheme.onAccent : AppTheme.primaryText)
                .padding(AppTheme.Spacing.md)
                .background(
                    message.role == .user ? AppTheme.accent : AppTheme.secondarySurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return NavigationStack { AssistantView() }
        .environmentObject(app)
        .environmentObject(app.inbox)
        .modelContainer(PreviewSupport.container)
}

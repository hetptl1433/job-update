import SwiftData
import SwiftUI

/// A personal-data assistant. It reasons over the user's jobs, inbox, calendar
/// and connections via the connected ChatGPT (OpenAI) — not a generic chatbot.
/// The request is a prompt plus a compact, structured context; the app holds no
/// key in code (the user's key lives in the Keychain).
struct AssistantView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var messages: [ChatMessage] = []
    @State private var input: String
    @State private var sending = false
    @State private var showConnect = false
    @State private var showMemory = false
    @State private var didRestoreConversation = false
    @AppStorage("orbit.ai.financeContextEnabled") private var shareFinanceWithAssistant = false

    private let suggestions = [
        "Did any recruiter contact me today?",
        "Did anything important arrive in Outlook?",
        "What do I need to do today?",
        "Which companies haven't responded?",
        "Who should I follow up with?",
        "What interviews do I have this week?",
        "How much money came in and went out this month?",
        "How much confirmed income did I earn this month?",
        "Summarize my day."
    ]

    init(initialPrompt: String = "") {
        _input = State(initialValue: initialPrompt)
    }

    var body: some View {
        Group {
            if app.connections.aiConnected {
                VStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        conversation
                    }
                    inputBar
                }
            } else {
                connectPrompt
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Orbit Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !messages.isEmpty {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            messages = []
                            AssistantConversationStore.clear()
                        }
                    }
                    Button("Personal memory", systemImage: "brain.head.profile") {
                        showMemory = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .sheet(isPresented: $showConnect) { ConnectChatGPTView().environmentObject(app) }
        .sheet(isPresented: $showMemory) {
            NavigationStack {
                AssistantMemorySettingsView().environmentObject(app)
            }
        }
        .onChange(of: messages) { _, messages in
            guard didRestoreConversation else { return }
            AssistantConversationStore.save(messages)
        }
        .task {
            if !didRestoreConversation {
                messages = AssistantConversationStore.load()
                didRestoreConversation = true
            }
        }
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        InfoStateView(
            systemImage: "sparkles",
            title: "Connect ChatGPT",
            message: "The assistant chats using your To Do list, jobs, inbox, calendars, health and any Finance summary you explicitly allow. Connect OpenAI with your API key to enable it.",
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
                    Text("Start a conversation")
                        .font(.title2.weight(.bold)).foregroundStyle(AppTheme.primaryText)
                    Text("Chat naturally by typing, or start live voice for a hands-free back-and-forth.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.top, AppTheme.Spacing.xl)

                Button {
                    app.assistantLaunch = .voice
                } label: {
                    Label("Start live conversation", systemImage: "waveform.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

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
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(
                                .scale(scale: 0.86, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                .combined(with: .opacity)
                            )
                    }

                    if sending {
                        ThinkingBubble()
                            .id("assistant-thinking")
                            .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
                    }

                    AssistantMemorySuggestionSlot(memory: app.assistantMemory)

                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(AppTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: messages.count)
        }
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TextField("Ask anything…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    AppTheme.secondarySurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
                .onSubmit(send)

            Button {
                app.assistantLaunch = .voice
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Open live voice")

            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .tint(AppTheme.brand)
            .disabled(
                input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || sending
            )
        }
        .padding(AppTheme.Spacing.md)
        .background(.ultraThinMaterial)
    }


    // MARK: Context + send

    private var contextBuilder: AssistantContextBuilder {
        AssistantContextBuilder(
            app: app,
            inbox: inbox,
            jobs: jobs,
            shareFinance: shareFinanceWithAssistant
        )
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }

        messages.append(ChatMessage(role: .user, text: text))
        input = ""
        sending = true
        if let memoryReply = runMemoryCommand(text) {
            messages.append(ChatMessage(role: .assistant, text: memoryReply))
            sending = false
            return
        }
        _ = app.assistantMemory.suggestMemory(from: text)
        if let toolReply = runStructuredTaskTool(text) {
            messages.append(ChatMessage(role: .assistant, text: toolReply))
            sending = false
            return
        }
        let ctx = contextBuilder.context(for: text)
        let recentHistory = Array(messages.dropLast().suffix(16))
        Task {
            do {
                let reply = try await app.assistant.answer(
                    text,
                    context: ctx,
                    history: recentHistory
                )
                messages.append(ChatMessage(role: .assistant, text: reply))
                sending = false
            } catch {
                let reply = "I couldn't get a response: \(error.localizedDescription)"
                messages.append(ChatMessage(role: .assistant, text: reply))
                sending = false
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }

    /// A small deterministic command surface for writes. Read questions still
    /// go to the model with structured repository context; task writes are
    /// explicit and never inferred from a vague model response.
    private func runStructuredTaskTool(_ prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let prefixes = [
            "create task:", "add task:", "create to do:", "add to do:",
            "remind me to ", "remind me "
        ]
        if let prefix = prefixes.first(where: { lower.hasPrefix($0) }) {
            let request = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else { return "Tell me what you want added to To Do." }
            let parsed = AssistantTaskInput(request)
            app.tasks.add(TaskItem(
                title: parsed.title,
                dueDate: parsed.date,
                source: .manual,
                alertStyle: parsed.date == nil ? TaskAlertStyle.none : TaskAlertStyle.alarm
            ))
            if let date = parsed.date {
                if app.connections.appleCalendarConnected {
                    return "Added “\(parsed.title)” to To Do for \(date.formatted(date: .abbreviated, time: .shortened)) and linked its schedule to Apple Calendar."
                }
                Task { await app.connectAppleCalendar() }
                return "Added “\(parsed.title)” to To Do for \(date.formatted(date: .abbreviated, time: .shortened)). I’ll ask for Apple Calendar access so its schedule can be linked."
            }
            return "Added “\(parsed.title)” to To Do without a schedule, so it stays only in your list."
        }
        if lower == "create tasks for emails i need to respond to" {
            guard !app.tasks.suggestions.isEmpty else {
                return "There are no unreviewed email task suggestions. Scan email first, then try again."
            }
            let suggestions = app.tasks.suggestions
            suggestions.forEach(app.acceptTaskSuggestion)
            return "Created \(suggestions.count) task\(suggestions.count == 1 ? "" : "s") from messages marked action-required."
        }
        return nil
    }

    private func runMemoryCommand(_ prompt: String) -> String? {
        guard let command = AssistantMemoryCommand.parse(prompt) else { return nil }
        switch command {
        case .remember(let text):
            switch app.assistantMemory.remember(text) {
            case .saved(let memory):
                return "I'll remember that \(memory.text). You can review or delete it anytime in Personal Memory."
            case .duplicate:
                return "I already have that in Personal Memory."
            case .disabled:
                return "Personal Memory is off. You can turn it on in Orbit Settings."
            case .rejected(let reason):
                return reason
            case .failed(let reason):
                return reason
            }
        case .forget(let text):
            return app.assistantMemory.forget(matching: text)
                ? "I've removed that from Personal Memory."
                : "I couldn't remove one clear matching memory. Open Personal Memory to choose it directly."
        case .forgetAll:
            guard !app.assistantMemory.memories.isEmpty else {
                return "Personal Memory is already empty."
            }
            return app.assistantMemory.deleteAll()
                ? "I've cleared everything from Personal Memory."
                : "I couldn't clear Personal Memory on this iPhone. Try again in Settings."
        }
    }
}

private struct AssistantMemorySuggestionSlot: View {
    @ObservedObject var memory: AssistantMemoryRepository

    var body: some View {
        if let suggestion = memory.pendingSuggestions.first {
            AssistantMemorySuggestionCard(suggestion: suggestion, memory: memory)
        }
    }
}

private struct AssistantMemorySuggestionCard: View {
    let suggestion: AssistantMemorySuggestion
    @ObservedObject var memory: AssistantMemoryRepository

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Remember for next time?", systemImage: "brain.head.profile")
                .font(.subheadline.weight(.semibold))
            Text(suggestion.text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            HStack {
                Button("Not now") { _ = memory.dismissSuggestion(suggestion) }
                    .buttonStyle(.bordered)
                Button("Remember") { _ = memory.acceptSuggestion(suggestion) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.secondarySurface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }
}

private struct AssistantTaskInput {
    let title: String
    let date: Date?

    init(_ input: String) {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ), let match = detector.firstMatch(
            in: input,
            options: [],
            range: NSRange(input.startIndex..., in: input)
        ), let detected = match.date else {
            title = Self.clean(input)
            date = nil
            return
        }

        if detected <= .now, Calendar.current.isDateInToday(detected) {
            date = Calendar.current.date(byAdding: .day, value: 1, to: detected)
        } else {
            date = detected
        }
        let withoutDate = (input as NSString).replacingCharacters(in: match.range, with: "")
        let cleaned = Self.clean(withoutDate)
        title = cleaned.isEmpty ? "To Do" : cleaned
    }

    private static func clean(_ input: String) -> String {
        input
            .replacingOccurrences(
                of: #"\s+\b(for|at|on)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

private struct MessageBubble: View {
    let role: ChatMessage.Role
    let text: String
    var isStreaming = false

    init(message: ChatMessage) {
        role = message.role
        text = message.text
    }

    init(role: ChatMessage.Role, text: String, isStreaming: Bool = false) {
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
            if role == .user { Spacer(minLength: 44) }

            if role == .assistant {
                ZStack {
                    Circle().fill(AppTheme.secondarySurface)
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
                .accessibilityHidden(true)
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if isStreaming {
                    Capsule()
                        .fill(role == .user ? AppTheme.onBrand : AppTheme.coral)
                        .frame(width: 2, height: 15)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(role == .user ? AppTheme.onBrand : AppTheme.primaryText)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 10)
            .background(
                role == .user ? AppTheme.brand : AppTheme.secondarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            )
            .overlay {
                if role == .assistant {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                }
            }

            if role == .assistant { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(role == .user ? "You" : "Orbit")
        .accessibilityValue(text)
    }
}

private struct ThinkingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
            ZStack {
                Circle().fill(AppTheme.secondarySurface)
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))

            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Thinking")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 10)
            .background(
                AppTheme.secondarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Orbit is thinking")
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return NavigationStack { AssistantView() }
        .environmentObject(app)
        .environmentObject(app.inbox)
        .modelContainer(PreviewSupport.container)
}

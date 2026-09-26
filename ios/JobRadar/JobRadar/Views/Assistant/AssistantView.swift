import SwiftData
import SwiftUI

/// A personal-data assistant. It reasons over the user's jobs, inbox, calendar
/// and connections — not a generic chatbot. It answers with a model running
/// on the iPhone or with the owner's own OpenAI key, and the composer picks
/// the model and how long it thinks. The request is a prompt plus a compact,
/// structured context; the app holds no key in code (an OpenAI key lives in
/// the Keychain).
struct AssistantView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var messages: [ChatMessage] = []
    @State private var input: String
    @State private var sending = false
    @State private var pendingReply: PendingReply?
    @State private var streamingReply: AssistantReplySnapshot?
    @State private var streamingThinkingSeconds: Double?
    @State private var replyTask: Task<Void, Never>?
    @State private var showConnect = false
    @State private var showMemory = false
    @State private var showModelPicker = false
    @State private var didRestoreConversation = false
    @State private var didSubmitInitialPrompt = false
    @AppStorage("orbit.ai.financeContextEnabled") private var shareFinanceWithAssistant = false
    @AppStorage("orbit.ai.healthContextEnabled") private var shareHealthWithAssistant = false
    private let initialPrompt: String

    /// Keeps lines readable on a wide iPad.
    private static let readableWidth: CGFloat = 760

    private let suggestions = [
        ChatSuggestion("Summarize my day", symbol: "sun.max", tint: AppTheme.warning, prompt: "Summarize my day."),
        ChatSuggestion("Recruiter emails today", symbol: "envelope.badge", tint: AppTheme.info, prompt: "Did any recruiter contact me today?"),
        ChatSuggestion("Important in Outlook", symbol: "tray.full", tint: AppTheme.info, prompt: "Did anything important arrive in Outlook?"),
        ChatSuggestion("What to do today", symbol: "checklist", tint: AppTheme.success, prompt: "What do I need to do today?"),
        ChatSuggestion("Companies yet to reply", symbol: "building.2", tint: AppTheme.purple, prompt: "Which companies haven't responded?"),
        ChatSuggestion("Who to follow up with", symbol: "person.2", tint: AppTheme.purple, prompt: "Who should I follow up with?"),
        ChatSuggestion("Interviews this week", symbol: "calendar", tint: AppTheme.coral, prompt: "What interviews do I have this week?"),
        ChatSuggestion("Money in and out", symbol: "arrow.left.arrow.right", tint: AppTheme.success, prompt: "How much money came in and went out this month?"),
        ChatSuggestion("Income this month", symbol: "dollarsign.circle", tint: AppTheme.success, prompt: "How much confirmed income did I earn this month?")
    ]

    init(initialPrompt: String = "") {
        self.initialPrompt = initialPrompt
        _input = State(initialValue: initialPrompt)
    }

    var body: some View {
        Group {
            switch app.assistantEngine {
            case .onDevice:
                LocalModelGate(model: app.localModel) {
                    chat
                } setup: {
                    LocalModelSetupView(model: app.localModel) {
                        app.assistantEngine = .openAI
                    }
                }
            case .openAI:
                if app.connections.aiConnected {
                    chat
                } else {
                    connectPrompt
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatTitle(engine: app.assistantEngine) { showModelPicker = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // A reply in progress would land in the new conversation.
                    if !messages.isEmpty, !sending {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            messages = []
                            AssistantConversationStore.clear()
                        }
                    }
                    Button("Model and thinking", systemImage: "cpu") {
                        showModelPicker = true
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
        .sheet(isPresented: $showModelPicker, onDismiss: {
            if app.assistantEngine == .onDevice { app.localModel.preload() }
        }) {
            ChatModelPickerSheet().environmentObject(app)
        }
        .onChange(of: app.assistantEngine) { _, engine in
            // Give the on-device model's memory back while OpenAI answers.
            if engine == .openAI { app.localModel.unload() }
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
            submitInitialPromptIfNeeded()
        }
        .onDisappear {
            replyTask?.cancel()
            app.localModel.unload()
        }
    }

    /// The conversation, shown once the selected engine can answer.
    private var chat: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyState
            } else {
                conversation
            }
            composer
        }
        .onAppear {
            if app.assistantEngine == .onDevice { app.localModel.preload() }
            submitInitialPromptIfNeeded()
        }
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            InfoStateView(
                systemImage: "sparkles",
                title: "Connect ChatGPT",
                message: "The assistant chats using your To Do list, jobs, inbox, calendars, health and any Finance summary you explicitly allow. Connect OpenAI with your API key to enable it.",
                actionTitle: "Connect ChatGPT"
            ) { showConnect = true }
            Button("Use the on-device model instead") {
                app.assistantEngine = .onDevice
            }
            .font(.subheadline.weight(.semibold))
            .tint(AppTheme.coral)
        }
        .padding(AppTheme.Spacing.lg)
    }

    // MARK: Connected — empty

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                VStack(spacing: AppTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AppTheme.accent.opacity(0.24), .clear],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 64
                                )
                            )
                            .frame(width: 128, height: 128)
                        OrbitMark(size: 58)
                    }
                    .frame(height: 104)
                    .accessibilityHidden(true)
                    Text("A little clarity, on demand.")
                        .font(.title2.weight(.semibold))
                        .tracking(-0.6)
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Your day has a lot of moving parts.\nLet’s make sense of them together.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.sm)

                if let featured = suggestions.first {
                    ChatSuggestionCard(suggestion: featured, isFeatured: true) { ask(featured.prompt) }
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
                    ],
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(suggestions.dropFirst()) { suggestion in
                        ChatSuggestionCard(suggestion: suggestion) { ask(suggestion.prompt) }
                    }
                }

                Button {
                    app.assistantLaunch = .voice
                } label: {
                    Label("Talk with Orbit live", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: Self.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    ForEach(messages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                            .transition(
                                .scale(scale: 0.9, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                .combined(with: .opacity)
                            )
                    }

                    if sending, let pendingReply {
                        StreamingReplyRow(
                            pending: pendingReply,
                            snapshot: streamingReply,
                            thinkingSeconds: streamingThinkingSeconds,
                            model: app.localModel
                        )
                        .id("assistant-streaming")
                        .transition(.opacity)
                    }

                    AssistantMemorySuggestionSlot(memory: app.assistantMemory)

                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: Self.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: streamingReply) { _, _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: messages.count)
        }
    }

    /// The message field, with the model and thinking choices beneath it.
    private var composer: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            TextField("Message Orbit", text: $input, axis: .vertical)
                .font(.callout)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1...6)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.top, 2)
                .onSubmit(send)

            HStack(spacing: AppTheme.Spacing.sm) {
                ChatModelChip(localModel: app.localModel) { showModelPicker = true }
                ChatThinkingChip(localModel: app.localModel) { showModelPicker = true }
                Spacer(minLength: 0)
                composerAction
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            AppTheme.primarySurface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: Self.readableWidth)
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
    }

    /// Stop while replying, send once there's text, and live voice otherwise.
    @ViewBuilder
    private var composerAction: some View {
        if replyTask != nil {
            ComposerButton(symbol: "stop.fill", label: "Stop response", isProminent: true, action: stopReply)
        } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ComposerButton(symbol: "arrow.up", label: "Send", isProminent: true) { send() }
                .disabled(sending)
        } else {
            ComposerButton(symbol: "waveform", label: "Open live voice", isProminent: false) {
                app.assistantLaunch = .voice
            }
        }
    }

    // MARK: Context + send

    private var contextBuilder: AssistantContextBuilder {
        AssistantContextBuilder(
            app: app,
            inbox: inbox,
            jobs: jobs,
            shareFinance: shareFinanceWithAssistant,
            shareHealth: shareHealthWithAssistant
        )
    }

    private var currentModelName: String {
        switch app.assistantEngine {
        case .onDevice: app.localModel.option?.name ?? "On-device model"
        case .openAI: AppConfig.chatModelChoice(for: AppConfig.openAIChatModel).name
        }
    }

    private var currentThinkingMode: ChatThinkingMode? {
        switch app.assistantEngine {
        case .onDevice: ChatPreferences.onDeviceThinking(for: app.localModel.option)
        case .openAI: ChatPreferences.openAIThinking(for: AppConfig.openAIChatModel)
        }
    }

    private func ask(_ prompt: String) {
        input = prompt
        send()
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
        let pending = PendingReply(
            engine: app.assistantEngine,
            model: currentModelName,
            thinking: currentThinkingMode
        )
        let replies = app.assistant.streamAnswer(text, context: ctx, history: recentHistory)
        pendingReply = pending
        streamingReply = nil
        streamingThinkingSeconds = nil
        replyTask = Task {
            var reply = AssistantReplySnapshot(text: "")
            var thinkingSeconds: Double?
            do {
                for try await snapshot in replies {
                    if thinkingSeconds == nil, snapshot.reasoning != nil, !snapshot.isThinking {
                        thinkingSeconds = Date().timeIntervalSince(pending.startedAt)
                        streamingThinkingSeconds = thinkingSeconds
                    }
                    reply = snapshot
                    streamingReply = snapshot
                }
                if !reply.text.isEmpty {
                    messages.append(pending.message(reply, thinkingSeconds: thinkingSeconds))
                } else if !Task.isCancelled {
                    messages.append(ChatMessage(role: .assistant, text: "I couldn't come up with an answer. Try asking another way."))
                }
            } catch {
                // Keep whatever was already streamed rather than replacing it.
                if reply.text.isEmpty {
                    messages.append(ChatMessage(role: .assistant, text: "I couldn't get a response: \(error.localizedDescription)"))
                } else {
                    reply.text += "\n\n(Stopped early: \(error.localizedDescription))"
                    messages.append(pending.message(reply, thinkingSeconds: thinkingSeconds))
                }
            }
            streamingReply = nil
            streamingThinkingSeconds = nil
            pendingReply = nil
            sending = false
            replyTask = nil
        }
    }

    /// Stops the reply in progress; anything already streamed is kept.
    private func stopReply() {
        replyTask?.cancel()
    }

    private func submitInitialPromptIfNeeded() {
        let prompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard app.isAssistantChatReady,
              didRestoreConversation,
              !didSubmitInitialPrompt,
              !prompt.isEmpty else { return }
        didSubmitInitialPrompt = true
        input = prompt
        send()
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

// MARK: - Replies

/// A reply on its way: what's answering and how, for the progress row and
/// the finished message's caption.
private struct PendingReply {
    let engine: AssistantEngine
    let model: String
    /// `nil` when the model answers without a thinking step.
    let thinking: ChatThinkingMode?
    let startedAt = Date()

    /// Whether to show thinking progress until the answer starts.
    var showsThinking: Bool {
        switch engine {
        case .onDevice: thinking == .thinking
        case .openAI: thinking.map { $0 != .instant } ?? false
        }
    }

    func message(_ reply: AssistantReplySnapshot, thinkingSeconds: Double?) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: reply.text,
            reasoning: reply.reasoning,
            thinkingSeconds: thinkingSeconds,
            detail: detail
        )
    }

    /// For example "Qwen3 1.7B · Think · 38s" or "GPT-6 Luna · 4s". The
    /// default mode goes unmentioned.
    private var detail: String {
        var parts = [model]
        if let thinking, thinking != (engine == .onDevice ? .instant : .balanced) {
            parts.append(thinking.title)
        }
        parts.append(ThinkingDisclosure.format(Date().timeIntervalSince(startedAt)))
        return parts.joined(separator: " · ")
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(AppTheme.onBrand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        AppTheme.primaryButton,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You")
            .accessibilityValue(message.text)
        case .assistant:
            AssistantMessageLayout {
                if message.reasoning != nil || message.thinkingSeconds != nil {
                    ThinkingDisclosure(
                        reasoning: message.reasoning,
                        seconds: message.thinkingSeconds,
                        startedAt: nil
                    )
                }
                ReplyText(text: message.text)
                if let detail = message.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .accessibilityLabel("Answered by \(detail)")
                }
            }
        }
    }
}

/// The reply while it's written: progress until the first words, then the
/// words as they arrive.
private struct StreamingReplyRow: View {
    let pending: PendingReply
    let snapshot: AssistantReplySnapshot?
    let thinkingSeconds: Double?
    @ObservedObject var model: LocalModelManager

    var body: some View {
        let text = snapshot?.text ?? ""
        let isLoading = pending.engine == .onDevice && model.isLoading
        AssistantMessageLayout {
            if isLoading {
                ReplyProgress(label: "Loading \(pending.model)")
            } else if pending.showsThinking || snapshot?.reasoning != nil {
                ThinkingDisclosure(
                    reasoning: snapshot?.reasoning,
                    seconds: thinkingSeconds,
                    startedAt: text.isEmpty ? pending.startedAt : nil
                )
            }
            if !text.isEmpty {
                ReplyText(text: text, isStreaming: true)
            } else if !isLoading, !pending.showsThinking {
                ReplyProgress(label: pending.engine == .onDevice ? "Reading your Orbit data" : "Writing")
            }
        }
    }
}

private struct AssistantMessageLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle().fill(AppTheme.secondarySurface)
                OrbitMark(size: 20)
            }
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}

/// Reply text with Markdown emphasis, code and links; a cursor trails it
/// while it's written.
private struct ReplyText: View {
    let text: String
    var isStreaming = false

    var body: some View {
        Text(attributed)
            .font(.callout)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.coral)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Orbit")
            .accessibilityValue(text)
    }

    private var attributed: AttributedString {
        var result = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
        if isStreaming {
            var cursor = AttributedString(" ▍")
            cursor.foregroundColor = AppTheme.coral
            result += cursor
        }
        return result
    }
}

/// "Thinking" with a live timer while the model thinks, then "Thought for
/// 12s", which expands to show the thinking when there's any to show.
private struct ThinkingDisclosure: View {
    let reasoning: String?
    let seconds: Double?
    /// Set while the model is still thinking.
    let startedAt: Date?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .symbolEffect(.pulse, isActive: startedAt != nil)
                    title
                    if reasoning != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(reasoning == nil)
            .accessibilityHint(reasoning == nil ? "" : (isExpanded ? "Hides the thinking" : "Shows the thinking"))

            if let reasoning {
                if isExpanded {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, AppTheme.Spacing.md)
                        .overlay(alignment: .leading) {
                            Capsule().fill(AppTheme.border).frame(width: 2)
                        }
                } else if startedAt != nil {
                    // The latest thought, so there's something to watch.
                    Text(String(reasoning.suffix(240)).replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if let startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text("Thinking · \(Self.format(context.date.timeIntervalSince(startedAt)))")
                    .monospacedDigit()
            }
        } else if let seconds {
            Text("Thought for \(Self.format(seconds))")
        } else {
            Text("Thoughts")
        }
    }

    /// For example "8s" or "1m 5s".
    static func format(_ seconds: Double) -> String {
        Duration.seconds(max(seconds, 1).rounded())
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }
}

private struct ReplyProgress: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppTheme.coral)
                        .frame(width: 6, height: 6)
                        .opacity(isAnimating ? 1 : 0.3)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
        .onAppear { isAnimating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Chrome

private struct ChatTitle: View {
    let engine: AssistantEngine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("Orbit Chat")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Label(caption, systemImage: engine.systemImage)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Orbit Chat, \(caption)")
        .accessibilityHint("Choose the model")
    }

    private var caption: String {
        switch engine {
        case .onDevice: "Private · on this \(DeviceProfile.name)"
        case .openAI: "OpenAI · your API key"
        }
    }
}

private struct ComposerButton: View {
    let symbol: String
    let label: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isProminent ? AppTheme.onBrand : AppTheme.coral)
                .frame(width: 36, height: 36)
                .background(isProminent ? AppTheme.primaryButton : AppTheme.secondarySurface, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        isProminent ? Color.white.opacity(0.16) : AppTheme.border,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ChatSuggestion: Identifiable {
    let title: String
    let symbol: String
    let tint: Color
    /// What's asked when the suggestion is tapped.
    let prompt: String

    var id: String { prompt }

    init(_ title: String, symbol: String, tint: Color, prompt: String) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.prompt = prompt
    }
}

private struct ChatSuggestionCard: View {
    let suggestion: ChatSuggestion
    var isFeatured = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isFeatured {
                    HStack(spacing: AppTheme.Spacing.md) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            title
                            Text("Inbox, To Do, calendar and more in one answer")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        icon
                        title
                    }
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.primarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel(suggestion.prompt)
    }

    private var icon: some View {
        Image(systemName: suggestion.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(suggestion.tint)
            .frame(width: 32, height: 32)
            .background(
                suggestion.tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var title: some View {
        Text(suggestion.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Memory suggestions

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

// MARK: - On-device setup

/// Shows the conversation once the on-device model is on this device, and the
/// download screen until then.
private struct LocalModelGate<Chat: View, Setup: View>: View {
    @ObservedObject var model: LocalModelManager
    @ViewBuilder var chat: () -> Chat
    @ViewBuilder var setup: () -> Setup

    var body: some View {
        if model.isReady {
            chat()
        } else {
            setup()
        }
    }
}

/// Until a model is downloaded: this device's power and the models it can
/// run, with the best fit marked Recommended.
private struct LocalModelSetupView: View {
    @ObservedObject var model: LocalModelManager
    let onUseOpenAI: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ZStack {
                        Circle().fill(AppTheme.accent.opacity(0.08)).frame(width: 82, height: 82)
                        Image(systemName: isUnsupported ? "iphone.slash" : "lock.iphone")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(AppTheme.coral)
                    }
                    .accessibilityHidden(true)
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .tracking(-0.6)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.lg)

                if !isUnsupported {
                    DevicePowerCard(model: model)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Choose a model").sectionLabel()
                        LocalModelList(model: model)
                    }
                    Text("Use Wi-Fi, and keep Orbit open while a model downloads.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                Button("Use OpenAI instead", action: onUseOpenAI)
                    .font(.subheadline.weight(.semibold))
                    .tint(AppTheme.coral)
                    .frame(maxWidth: .infinity)
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshAvailability() }
    }

    private var isUnsupported: Bool {
        if case .unsupported = model.availability { return true }
        return false
    }

    private var title: String {
        isUnsupported ? "On-device chat isn't available" : "Run Orbit Chat on this \(DeviceProfile.name)"
    }

    private var message: String {
        if case .unsupported(let reason) = model.availability { return reason }
        return "Download a model once. After that, chat works offline, and your questions and Orbit data never leave this \(DeviceProfile.name). The recommended model fits its chip and memory best."
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return NavigationStack { AssistantView() }
        .environmentObject(app)
        .environmentObject(app.inbox)
        .modelContainer(PreviewSupport.container)
}

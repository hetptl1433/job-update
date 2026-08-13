import SwiftData
import SwiftUI

extension RealtimeTurnRole {
    var chatRole: ChatMessage.Role {
        switch self {
        case .user: .user
        case .assistant: .assistant
        }
    }
}

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
    @State private var didAutoStartVoice = false
    @State private var didRestoreConversation = false
    @StateObject private var realtime = OpenAIRealtimeSession()
    @AppStorage("orbit.ai.financeContextEnabled") private var shareFinanceWithAssistant = false

    private let startsListening: Bool

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

    init(initialPrompt: String = "", startsListening: Bool = false) {
        _input = State(initialValue: initialPrompt)
        self.startsListening = startsListening
    }

    var body: some View {
        Group {
            if app.connections.aiConnected {
                VStack(spacing: 0) {
                    if messages.isEmpty && !realtime.isActive {
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
            if !messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New conversation", systemImage: "square.and.pencil") {
                            endLiveConversation()
                            messages = []
                            AssistantConversationStore.clear()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Conversation options")
                }
            }
        }
        .sheet(isPresented: $showConnect) { ConnectChatGPTView().environmentObject(app) }
        .onChange(of: realtime.completedTurn) { _, turn in
            guard let turn else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                messages.append(ChatMessage(role: turn.role.chatRole, text: turn.text))
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
            guard startsListening, !didAutoStartVoice, app.connections.aiConnected else { return }
            didAutoStartVoice = true
            await beginLiveConversation()
        }
        .onDisappear {
            realtime.disconnect()
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
                    Task { await beginLiveConversation() }
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
                    if messages.isEmpty,
                       realtime.liveUserText.isEmpty,
                       realtime.liveAssistantText.isEmpty {
                        LiveReadyCard(isConnecting: realtime.state == .connecting)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(
                                .scale(scale: 0.86, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                .combined(with: .opacity)
                            )
                    }

                    if !realtime.liveUserText.isEmpty {
                        MessageBubble(
                            role: .user,
                            text: realtime.liveUserText,
                            isStreaming: true
                        )
                        .id("live-user")
                        .transition(.scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
                    }

                    if !realtime.liveAssistantText.isEmpty {
                        MessageBubble(
                            role: .assistant,
                            text: realtime.liveAssistantText,
                            isStreaming: true
                        )
                        .id("live-assistant")
                        .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
                    }

                    if (sending && !realtime.isActive)
                        || (realtime.isResponding && realtime.liveAssistantText.isEmpty) {
                        ThinkingBubble()
                            .id("assistant-thinking")
                            .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
                    }

                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(AppTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: realtime.liveUserText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: realtime.liveAssistantText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: realtime.isResponding) { _, _ in
                scrollToBottom(proxy)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: messages.count)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: realtime.liveUserText.isEmpty)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: realtime.liveAssistantText.isEmpty)
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if realtime.isActive {
                HStack {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        LivePulse(isActive: realtime.state == .connected && !realtime.isMuted)
                        Label(liveStatus, systemImage: liveStatusIcon)
                    }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.coral)
                    Spacer()
                    Button("End live") { endLiveConversation() }
                        .font(.caption.weight(.semibold))
                }
            }

            if let error = realtime.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.destructive)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                TextField("Ask anything…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
                    .onSubmit(send)

                Button {
                    if realtime.isActive {
                        realtime.toggleMute()
                    } else {
                        Task { await beginLiveConversation() }
                    }
                } label: {
                    Image(systemName: realtime.isActive
                          ? (realtime.isMuted ? "mic.slash.circle.fill" : "waveform.circle.fill")
                          : "waveform.circle.fill")
                        .font(.title)
                        .foregroundStyle(realtime.isActive && !realtime.isMuted ? AppTheme.coral : AppTheme.primaryText)
                        .frame(width: 44, height: 44)
                }
                .disabled(sending || realtime.state == .connecting)
                .accessibilityLabel(realtime.isActive
                                    ? (realtime.isMuted ? "Unmute live conversation" : "Mute live conversation")
                                    : "Start live conversation")

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .tint(AppTheme.brand)
                .disabled(
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || sending
                    || realtime.state == .connecting
                )
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    private var liveStatus: String {
        if realtime.state == .connecting { return "Connecting live voice…" }
        if realtime.isMuted { return "Microphone muted" }
        if realtime.isUserSpeaking { return "Listening…" }
        if realtime.isAssistantSpeaking { return "Orbit is speaking…" }
        if realtime.isResponding { return "Orbit is thinking…" }
        return "Live — just start talking"
    }

    private var liveStatusIcon: String {
        if realtime.state == .connecting { return "network" }
        if realtime.isMuted { return "mic.slash.fill" }
        if realtime.isAssistantSpeaking { return "speaker.wave.2.fill" }
        return "waveform"
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

        if realtime.isConnected {
            messages.append(ChatMessage(role: .user, text: text))
            input = ""
            if let toolReply = runStructuredTaskTool(text) {
                messages.append(ChatMessage(role: .assistant, text: toolReply))
                realtime.recordLocalExchange(userText: text, assistantText: toolReply)
            } else {
                realtime.sendText(text)
            }
            return
        }

        messages.append(ChatMessage(role: .user, text: text))
        input = ""
        sending = true
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

    private func beginLiveConversation() async {
        guard !sending, !realtime.isActive else { return }
        guard let key = KeychainStore.get(KeychainKeys.openAIKey), !key.isEmpty else {
            showConnect = true
            return
        }

        let liveContext = contextBuilder.liveContext()
        let instructions = AssistantPrompt.realtimeInstructions(
            context: liveContext,
            history: messages
        )
        do {
            let credential = try await RealtimeClientSecretProvider(apiKey: key)
                .mintCredential(
                    model: AppConfig.openAIRealtimeModel,
                    instructions: instructions
                )
            await realtime.connect(
                credential: credential,
                model: AppConfig.openAIRealtimeModel,
                instructions: ""
            )
        } catch {
            realtime.disconnect()
            messages.append(ChatMessage(
                role: .assistant,
                text: "I couldn't start live voice: \(error.localizedDescription)"
            ))
        }
    }

    private func endLiveConversation() {
        realtime.disconnect()
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
            suggestions.forEach(app.tasks.acceptSuggestion)
            return "Created \(suggestions.count) task\(suggestions.count == 1 ? "" : "s") from messages marked action-required."
        }
        return nil
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

private struct LiveReadyCard: View {
    let isConnecting: Bool

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AppTheme.coral.opacity(0.09))
                    .frame(width: 92, height: 92)
                Circle()
                    .fill(AppTheme.coral.opacity(0.14))
                    .frame(width: 62, height: 62)
                Image(systemName: isConnecting ? "network" : "waveform")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Text(isConnecting ? "Starting live conversation…" : "I'm listening")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(isConnecting
                     ? "Orbit is preparing your private context and live audio."
                     : "Talk naturally, pause when you're done, and interrupt whenever you want.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if isConnecting {
                ProgressView().tint(AppTheme.coral)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxl)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

private struct LivePulse: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.coral.opacity(0.35), lineWidth: 2)
                .scaleEffect(pulse && isActive ? 1.9 : 1)
                .opacity(pulse && isActive ? 0 : 0.8)
            Circle()
                .fill(isActive ? AppTheme.coral : AppTheme.tertiaryText)
        }
        .frame(width: 8, height: 8)
        .onAppear { updateAnimation() }
        .onChange(of: isActive) { _, _ in updateAnimation() }
        .accessibilityHidden(true)
    }

    private func updateAnimation() {
        pulse = false
        guard isActive else { return }
        withAnimation(.easeOut(duration: 1.25).repeatForever(autoreverses: false)) {
            pulse = true
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

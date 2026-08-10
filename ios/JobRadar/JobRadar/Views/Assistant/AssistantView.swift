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
    @State private var voiceModeActive = false
    @State private var didAutoStartVoice = false
    @StateObject private var voice = VoiceAssistantAudio()
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
        .onChange(of: voice.transcript) { _, transcript in
            if voiceModeActive { input = transcript }
        }
        .onChange(of: voice.isFinal) { _, isFinal in
            guard isFinal, voiceModeActive, !sending else { return }
            input = voice.transcript
            send()
        }
        .task {
            guard startsListening, !didAutoStartVoice, app.connections.aiConnected else { return }
            didAutoStartVoice = true
            await beginVoiceInput()
        }
        .onDisappear {
            voice.stopListening()
            voice.stopSpeaking()
        }
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        InfoStateView(
            systemImage: "sparkles",
            title: "Connect ChatGPT",
            message: "The assistant answers using your tasks, reminders, jobs, inbox, calendars, health and any Finance summary you explicitly allow. Connect ChatGPT with your OpenAI key to enable it.",
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
                    Text("I answer using the current context already inside Orbit.")
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if voice.isListening {
                Label("Listening… tap stop when you're finished", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
            } else if let error = voice.errorMessage {
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

                Button { toggleVoiceInput() } label: {
                    Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title)
                        .foregroundStyle(voice.isListening ? AppTheme.coral : AppTheme.primaryText)
                        .frame(width: 44, height: 44)
                }
                .disabled(sending)
                .accessibilityLabel(voice.isListening ? "Stop and send" : "Talk to Orbit")

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .tint(AppTheme.brand)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: Context + send

    private func context(for prompt: String) -> AssistantContext {
        var lines: [String] = []
        lines.append("Connections: Gmail \(app.connections.gmailConnected ? "connected" : "not connected"), Outlook \(app.connections.outlookConnected ? "connected" : "not connected"), Calendar \(app.calendar.connectedProviders.map(\.label).sorted().joined(separator: ", ")), Health \(app.connections.healthConnected ? "connected" : "not connected").")

        if shareFinanceWithAssistant, case let .loaded(finance) = app.finance.state {
            let code = finance.currencyCode
            lines.append("User-approved Finance summary (currency \(code)):")
            lines.append("- cash=\(finance.totalCash); credit-card balance=\(finance.totalCreditBalance); investments=\(finance.totalInvestments); current-month inflow=\(finance.monthlyInflow); outflow=\(finance.monthlyOutflow); net=\(finance.monthlyNetFlow)")

            let lowerPrompt = prompt.lowercased()
            let asksAboutFinance = [
                "money", "finance", "account", "balance", "cash", "card", "credit",
                "spend", "spent", "transaction", "bill", "subscription", "income",
                "earn", "paid", "paycheck", "salary", "wage", "inflow", "outflow"
            ].contains { lowerPrompt.contains($0) }
            let asksAboutIncome = [
                "income", "earn", "paid", "paycheck", "salary", "wage", "employer",
                "annual", "year to date", "ytd"
            ].contains { lowerPrompt.contains($0) }

            if asksAboutFinance {
                for account in finance.accounts.prefix(20) {
                    lines.append("- account: \(account.maskedName); institution=\(account.institutionName); type=\(account.kind.label); balance=\(account.currentBalance) \(account.currencyCode)")
                }
            }

            if asksAboutFinance, !asksAboutIncome, !finance.recentTransactions.isEmpty {
                lines.append("Recent normalized transactions:")
                for transaction in finance.recentTransactions.prefix(15) {
                    lines.append("- \(transaction.date); \(transaction.displayName); \(transaction.direction.rawValue)=\(transaction.amount) \(transaction.currencyCode); category=\(transaction.category ?? "unknown")")
                }
            }

            if asksAboutIncome, case let .loaded(income) = app.finance.incomeState {
                lines.append("DETERMINISTIC INCOME TOOL RESULT (do not recompute or relabel inflow as income):")
                for summary in income.summaries {
                    lines.append("- currency=\(summary.currencyCode); confirmed posted this month=\(summary.thisMonth.confirmed); pending income=\(summary.thisMonth.pending); needs review excluded=\(summary.thisMonth.needsReview); confirmed last month=\(summary.lastMonth.confirmed); change amount=\(summary.changeAmount.map { String(describing: $0) } ?? "undefined"); change percent=\(summary.changePercent.map { String(describing: $0) } ?? "undefined"); confirmed YTD=\(summary.yearToDate); average monthly=\(summary.averageMonthly); estimated annual=\(summary.estimatedAnnual.map { String(describing: $0) } ?? "unavailable")")
                    for source in summary.sources.prefix(20) {
                        lines.append("- income source: \(source.name); type=\(source.type.rawValue); frequency=\(source.frequency.rawValue); this month=\(source.thisMonth); YTD=\(source.yearToDate); average deposit=\(source.averagePayment); next expected=\(source.nextExpectedPaymentDate ?? "unavailable"); user confirmed=\(source.userConfirmed)")
                    }
                    if !summary.history.isEmpty {
                        lines.append("- confirmed income history: " + summary.history.map { "\($0.month)=\($0.confirmed)" }.joined(separator: "; "))
                    }
                    for transaction in summary.confirmedTransactions.prefix(10) {
                        lines.append("- confirmed observed net deposit: \(transaction.date); \(transaction.sourceName ?? transaction.merchantName ?? transaction.name); amount=\(transaction.amount) \(transaction.currencyCode); pending=\(transaction.pending)")
                    }
                    for paycheck in summary.expectedPaychecks.prefix(8) {
                        lines.append("- expected (not guaranteed): \(paycheck.sourceName); date=\(paycheck.date); estimated amount=\(paycheck.estimatedAmount) \(summary.currencyCode)")
                    }
                }
            }
        }

        if !app.tasks.prioritizedOpen.isEmpty {
            lines.append("Open To Do tasks (not reminders or calendar events):")
            for task in app.tasks.prioritizedOpen.prefix(25) {
                let due = task.dueDate.map { "; due \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
                lines.append("- id=\(task.id.uuidString); \(task.title); priority=\(task.priority.rawValue); source=\(task.source.rawValue)\(due)")
            }
        }

        if !app.reminders.open.isEmpty {
            lines.append("Upcoming Orbit reminders (linked to Apple Calendar when connected):")
            for reminder in app.reminders.open.prefix(20) {
                lines.append("- id=\(reminder.id.uuidString); \(reminder.title); fires \(reminder.fireDate.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if !app.tasks.suggestions.isEmpty {
            lines.append("Unreviewed To Do suggestions extracted from email:")
            for task in app.tasks.suggestions.prefix(15) {
                lines.append("- \(task.title)")
            }
        }

        let recentCompleted = app.tasks.completed.prefix(10)
        if !recentCompleted.isEmpty {
            lines.append("Recently completed To Dos:")
            for task in recentCompleted {
                lines.append("- \(task.title); completed or updated \(task.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if !app.detectedJobUpdates.isEmpty {
            lines.append("Unreviewed job updates detected from connected email:")
            for update in app.detectedJobUpdates.prefix(15) {
                let role = update.role.isEmpty ? "" : " — \(update.role)"
                let next = update.nextAction.isEmpty ? "" : "; next: \(update.nextAction)"
                lines.append("- \(update.company)\(role) [\(update.status.rawValue)]\(next); evidence: \(update.reason)")
            }
        }

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
                lines.append("- [\(message.provider.label); \(message.mailboxEmail)] \(message.sender): \(message.subject) — \(message.aiSummary)\(message.actionRequired ? " [action required]" : "")")
            }
        }

        let events = app.calendar.events
        if !events.isEmpty {
            lines.append("Upcoming unified calendar events:")
            for event in events.prefix(20) {
                lines.append("- [\(event.provider.label)] \(event.start.formatted(date: .abbreviated, time: .shortened)): \(event.title)")
            }
        }

        if case let .loaded(summary) = app.health.state {
            lines.append("Current Apple Health summary:")
            lines.append(summary.metrics.map { "\($0.title): \($0.value)" }.joined(separator: "; "))
        }

        let enabledAutomations = app.automations.automations.filter(\.enabled)
        if !enabledAutomations.isEmpty {
            lines.append("Enabled Orbit automations:")
            for automation in enabledAutomations {
                lines.append("- \(automation.title); \(automation.frequency)")
            }
        }

        return AssistantContext(userName: app.user?.firstName ?? "the user", lines: lines)
    }

    private func send() {
        if voice.isListening { voice.stopListening() }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        messages.append(ChatMessage(role: .user, text: text))
        input = ""
        sending = true
        if let toolReply = runStructuredTaskTool(text) {
            messages.append(ChatMessage(role: .assistant, text: toolReply))
            if voiceModeActive { voice.speak(toolReply) }
            sending = false
            return
        }
        let ctx = context(for: text)
        let recentHistory = Array(messages.dropLast().suffix(8))
        Task {
            do {
                let reply = try await app.assistant.answer(
                    text,
                    context: ctx,
                    history: recentHistory
                )
                messages.append(ChatMessage(role: .assistant, text: reply))
                if voiceModeActive { voice.speak(reply) }
            } catch {
                let reply = "I couldn't get a response: \(error.localizedDescription)"
                messages.append(ChatMessage(role: .assistant, text: reply))
                if voiceModeActive { voice.speak(reply) }
            }
            sending = false
        }
    }

    private func toggleVoiceInput() {
        if voice.isListening {
            input = voice.transcript
            voice.stopListening()
            send()
        } else {
            Task { await beginVoiceInput() }
        }
    }

    private func beginVoiceInput() async {
        guard !sending else { return }
        voiceModeActive = true
        input = ""
        await voice.startListening()
    }

    /// A small deterministic command surface for writes. Read questions still
    /// go to the model with structured repository context; task writes are
    /// explicit and never inferred from a vague model response.
    private func runStructuredTaskTool(_ prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for prefix in ["create task:", "add task:"] where lower.hasPrefix(prefix) {
            let title = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return "Add a task title after the colon." }
            app.tasks.add(TaskItem(title: title, dueDate: .now, source: .manual))
            return "Created “\(title)” in Orbit Tasks for today."
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

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? AppTheme.onBrand : AppTheme.primaryText)
                .padding(AppTheme.Spacing.md)
                .background(
                    message.role == .user ? AppTheme.brand : AppTheme.secondarySurface,
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

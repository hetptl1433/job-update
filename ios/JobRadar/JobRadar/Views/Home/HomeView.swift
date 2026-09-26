import SwiftData
import SwiftUI

/// The command center. Answers "what do I need to do right now?" with To Do as
/// the dominant first surface, followed by the rest of the day's context.
struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @EnvironmentObject private var tasks: TaskRepository
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var showCalendar = false
    @State private var editingTask: TaskItem?
    @State private var placeholderIndex = 0
    @State private var completingTaskIDs: Set<UUID> = []
    @State private var completionFeedback = 0
    @State private var lastCompletedID: UUID?
    @State private var selectedMessage: InboxMessage?
    @State private var rescheduleFeedback = 0
    @State private var taskRowWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orbitWideLayout) private var isWide

    /// A wide iPad has room to show more of each list.
    private var taskLimit: Int { isWide ? 5 : 3 }
    private var eventLimit: Int { isWide ? 3 : 1 }
    private var messageLimit: Int { isWide ? 3 : 2 }

    private let placeholders = [
        "Anything important today?",
        "Did a recruiter email me?",
        "Who should I follow up with?",
        "What do I need to do today?"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                OrbitColumns {
                    greeting.orbitAppear(0)
                    VStack(spacing: AppTheme.Spacing.md) {
                        todoSection
                        taskSuggestions
                    }
                    .orbitAppear(1)
                    .orbitColumn(.leading)
                    if !attention.isEmpty || !app.detectedJobUpdates.isEmpty {
                        attentionSection.orbitAppear(2).orbitColumn(.leading)
                    }
                    todaySection.orbitAppear(2).orbitColumn(.trailing)
                    perspectiveSection.orbitAppear(3).orbitColumn(.trailing)
                    jobsSummary.orbitAppear(4).orbitColumn(.leading)
                    inboxSummary.orbitAppear(4).orbitColumn(.trailing)
                    assistantSection.orbitAppear(5).orbitColumn(.leading)
                    syncBanner.orbitAppear(5).orbitColumn(.trailing)
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.background)
            .orbitNavigationChrome()
            .refreshable { await app.refreshDashboard() }
            .sheet(isPresented: $showCalendar) { CalendarTimelineView() }
            .inboxMessageDetail($selectedMessage)
            .sheet(item: $editingTask) { item in
                TaskEditor(item: item) { saved in
                    if tasks.tasks.contains(where: { $0.id == saved.id }) { tasks.update(saved) }
                    else { tasks.add(saved) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let id = lastCompletedID {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Label("One less thing on your mind.", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(AppTheme.primaryText)
                        Spacer(minLength: 0)
                        Button("Undo") {
                            _ = tasks.setCompletion(id, isCompleted: false)
                            lastCompletedID = nil
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.coral)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    .padding(.horizontal, AppTheme.Spacing.page)
                    .padding(.bottom, AppTheme.Spacing.sm)
                }
            }
            .task(id: lastCompletedID) {
                guard let id = lastCompletedID else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, lastCompletedID == id else { return }
                lastCompletedID = nil
            }
            .task { await app.refreshHomeIfStale() }
        }
        .sensoryFeedback(.success, trigger: completionFeedback)
        .sensoryFeedback(.selection, trigger: rescheduleFeedback)
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .sectionLabel()
            (Text("\(timeGreeting), \(app.user?.firstName ?? "there")") + Text(".").foregroundColor(AppTheme.coral))
                .font(.title.weight(.semibold))
                .tracking(-0.8)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(dayBrief)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: dayBrief)
        }
    }

    /// One line on what the day holds, e.g. "2 due today · Interview at 3:00 PM".
    private var dayBrief: String {
        let open = tasks.prioritizedOpen
        let overdue = open.filter(\.isOverdue).count
        let dueToday = open.filter(\.isDueToday).count
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if let next = app.calendarState.value?.first(where: {
            !$0.isAllDay && $0.start > .now && Calendar.current.isDateInToday($0.start)
        }) {
            parts.append("\(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))")
        }
        if !attention.isEmpty {
            parts.append("\(attention.count) follow-up\(attention.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Nothing urgent. A clear view of what’s next." : parts.joined(separator: " · ")
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: AI input

    private var assistantSection: some View {
        OrbitAssistantCard(
            prompt: placeholders[placeholderIndex],
            onChat: { app.openAssistant() },
            onVoice: { app.assistantLaunch = .voice }
        )
    }

    // MARK: Sync banner

    private var syncBanner: some View {
        Button {
            Task { await app.syncEmail() }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                if app.isSyncing {
                    ProgressView().tint(AppTheme.brand)
                } else {
                    Image(systemName: "arrow.clockwise").foregroundStyle(AppTheme.brand)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.isSyncing ? (app.syncStageMessage ?? "Checking your email…") : "Scan email for job updates")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                    Text(app.lastSyncSummary ?? syncHelpText)
                        .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                }
                Spacer()
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).strokeBorder(AppTheme.brand.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(app.isSyncing)
    }

    private var syncHelpText: String {
        if !app.connections.emailConnected { return "Connect Gmail or Outlook to read job-related messages." }
        if !app.connections.aiConnected { return "Connect AI processing to turn email into tracker updates." }
        return "Read-only scan. You review every suggested change."
    }

    // MARK: To do

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("To do")
                    .font(.title2.weight(.semibold))
                    .tracking(-0.4)
                    .foregroundStyle(AppTheme.primaryText)
                Text(todoSummary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                OrbitIconButton(title: "Add To Do", symbol: "plus") {
                    app.quickTaskCaptureRequested = true
                }
            }
            .padding(.bottom, AppTheme.Spacing.md)

            if tasks.prioritizedOpen.isEmpty {
                InfoStateView(
                    systemImage: "checkmark.circle",
                    title: "A little breathing room",
                    message: "Add a task or scan email for suggested actions.",
                    actionTitle: "Add your first task"
                ) { app.quickTaskCaptureRequested = true }
            } else {
                ForEach(Array(tasks.prioritizedOpen.prefix(taskLimit).enumerated()), id: \.element.id) { index, task in
                    HomeTaskRow(
                        item: task,
                        isCompleting: completingTaskIDs.contains(task.id),
                        onToggle: { complete(task) },
                        onEdit: { editingTask = task }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { taskRowWidth = $0 }
                    .contextMenu {
                        Button { complete(task) } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        Button { editingTask = task } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        if !(task.dueDate.map(Calendar.current.isDateInTomorrow) ?? false) {
                            Button { moveToTomorrow(task) } label: {
                                Label("Do tomorrow", systemImage: "sunrise")
                            }
                        }
                    } preview: {
                        // The card's gradient can't be matched per row, so the
                        // preview draws the row on its own surface.
                        HomeTaskRow(item: task, onToggle: {}, onEdit: {})
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .frame(width: taskRowWidth > 0 ? taskRowWidth + AppTheme.Spacing.lg * 2 : nil)
                            .background(AppTheme.primarySurface)
                    }
                    .transition(.opacity)
                    if index < min(tasks.prioritizedOpen.count, taskLimit) - 1 {
                        Divider().overlay(AppTheme.separator).padding(.leading, 44)
                    }
                }
            }
            Divider().overlay(AppTheme.separator).padding(.top, AppTheme.Spacing.md)
            HStack(spacing: AppTheme.Spacing.md) {
                Text("\(tasks.completed.count) of \(tasks.tasks.count) complete")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                ProgressView(value: Double(tasks.completed.count), total: Double(max(tasks.tasks.count, 1)))
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Task progress")
                Button { app.selectedTab = .tasks } label: {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minHeight: 44)
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
        .orbitFocusSurface(padding: AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private var taskSuggestions: some View {
        if !tasks.suggestions.isEmpty {
            Button { app.selectedTab = .tasks } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.coral)
                    Text("\(tasks.suggestions.count) suggested task\(tasks.suggestions.count == 1 ? "" : "s") from your inbox")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                }
                .frame(minHeight: 24)
                .orbitFocusSurface(padding: AppTheme.Spacing.md)
            }
            .buttonStyle(OrbitPressStyle())
        }
    }

    private var todoSummary: String {
        let openCount = tasks.prioritizedOpen.count
        let dueTodayCount = tasks.prioritizedOpen.filter(\.isDueToday).count
        if dueTodayCount > 0 {
            return "\(openCount) open · \(dueTodayCount) due today"
        }
        return "\(openCount) open"
    }

    private func complete(_ item: TaskItem) {
        guard !completingTaskIDs.contains(item.id) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68)) {
            _ = completingTaskIDs.insert(item.id)
        }

        let delay = reduceMotion ? 0 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let current = tasks.tasks.first(where: { $0.id == item.id }),
                  !current.isCompleted else {
                completingTaskIDs.remove(item.id)
                return
            }
            let didComplete = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                tasks.setCompletion(current.id, isCompleted: true)
            }
            if didComplete { completionFeedback += 1; lastCompletedID = current.id }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                _ = completingTaskIDs.remove(item.id)
            }
        }
    }

    /// Matches the To Do list's Tomorrow action: 9 AM the next day.
    private func moveToTomorrow(_ item: TaskItem) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let didMove = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            tasks.reschedule(item, to: due)
        }
        if didMove { rescheduleFeedback += 1 }
    }

    // MARK: Needs your attention

    private var attention: [AttentionItem] {
        jobs.compactMap { job in
            guard job.status.isActive, let due = job.nextActionDate,
                  Calendar.current.startOfDay(for: due) <= Calendar.current.startOfDay(for: .now),
                  !job.nextAction.isEmpty else { return nil }
            return AttentionItem(
                id: "job-\(job.id)", category: .job,
                title: "\(job.company) — follow up",
                detail: job.nextAction, timestamp: due,
                importance: .high, source: "Jobs", actionTitle: "Open"
            )
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Needs your attention")

            if !app.detectedJobUpdates.isEmpty {
                ForEach(app.detectedJobUpdates) { update in
                    DetectedUpdateCard(
                        update: update,
                        onAccept: { app.acceptJobUpdate(update) },
                        onDismiss: { app.dismissJobUpdate(update) }
                    )
                }
            }

            if attention.isEmpty && app.detectedJobUpdates.isEmpty {
                InfoStateView(
                    systemImage: "checkmark.circle",
                    title: "You're all caught up",
                    message: app.connections.emailConnected
                        ? "Pull to refresh, or tap Refresh from email to check for updates."
                        : "Connect email to surface what needs you."
                )
                .cardSurface()
            } else if !attention.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(attention.enumerated()), id: \.element.id) { index, item in
                        AttentionRow(item: item)
                        if index < attention.count - 1 { Divider().overlay(AppTheme.separator) }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    // MARK: Jobs summary

    private var jobsSummary: some View {
        let active = jobs.filter { $0.status.isActive }
        let interviews = active.filter { $0.status == .interview || $0.status == .finalInterview }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Moving forward", actionTitle: "Job tracker") { app.selectedTab = .jobs }
            Button { app.selectedTab = .jobs } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "briefcase")
                        .foregroundStyle(AppTheme.coral)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(interviews.isEmpty ? "\(active.count) active applications" : "\(interviews.count) interview\(interviews.count == 1 ? "" : "s") in motion")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text(attention.isEmpty ? "Every opportunity, in one place" : "\(attention.count) follow-up\(attention.count == 1 ? "" : "s") due")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.tertiaryText)
                }
                .cardSurface()
            }
            .buttonStyle(OrbitPressStyle())
        }
    }

    // MARK: Inbox summary

    private var inboxSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Inbox", actionTitle: "Open") { app.selectedTab = .inbox }
            Group {
                switch inbox.state {
                case .disconnected:
                    InfoStateView(systemImage: "envelope", title: "Email not connected",
                                  message: "Connect Gmail or Outlook to see messages that need your attention.",
                                  actionTitle: "Connect Gmail") { Task { await app.connectGmailAccount() } }
                case .loading:
                    LoadingStateView(message: "Checking your inbox…")
                case .empty:
                    InfoStateView(systemImage: "tray", title: "No important messages",
                                  message: "You're all clear for now.")
                case let .loaded(messages):
                    VStack(spacing: 0) {
                        ForEach(messages.prefix(messageLimit)) { message in
                            InboxMessageButton(
                                message: message,
                                isInToDo: tasks.tasks.contains { $0.relatedEmailID == message.id }
                            ) { selectedMessage = message }
                        }
                    }
                case let .failed(message):
                    InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load inbox", message: message)
                case .idle:
                    EmptyView()
                }
            }
            .cardSurface(padding: inbox.state.value == nil ? AppTheme.Spacing.lg : 0)
        }
    }

    // MARK: Today / calendar

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(
                title: "Up next",
                actionTitle: app.calendarState.value?.isEmpty == false ? "See all" : nil
            ) { showCalendar = true }
            switch app.calendarState {
            case .disconnected, .idle:
                InfoStateView(systemImage: "calendar", title: "Calendar not connected",
                              message: "Connect Calendar to see interviews, meetings and deadlines.",
                              actionTitle: "Connect Calendar") { Task { await app.connectCalendar() } }
                    .cardSurface()
            case .loading:
                LoadingStateView(message: "Loading your calendar…").cardSurface()
            case .empty:
                InfoStateView(systemImage: "calendar", title: "No upcoming events",
                              message: "Your connected calendars are clear for the next 14 days.")
                    .cardSurface()
            case .failed(let message):
                InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load Calendar",
                              message: message, actionTitle: "Retry") { Task { await app.refreshCalendar() } }
                    .cardSurface()
            case .loaded(let events):
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(eventLimit).enumerated()), id: \.element.id) { index, event in
                        CalendarHomeRow(
                            event: event,
                            isInToDo: tasks.tasks.contains { $0.relatedCalendarEventID == event.id },
                            onAddToDo: { app.addCalendarEventToTasks(event) }
                        )
                        if index < min(events.count, eventLimit) - 1 { Divider().overlay(AppTheme.separator) }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    // MARK: Finance + Health at a glance

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "A little perspective")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppTheme.Spacing.md) { financeTile; healthTile }
            } else {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) { financeTile; healthTile }
            }
        }
    }

    private var financeTile: some View {
        let overview = app.finance.state.value
        return OrbitSummaryTile(
            title: "Spending", symbol: "creditcard",
            value: overview.map { $0.adjustedMonthlyOutflow.formatted(.currency(code: $0.currencyCode).precision(.fractionLength(0))) } ?? "—",
            detail: overview == nil ? "Open Finance to connect or review accounts" : "This month so far",
            action: { app.selectedTab = .finance }
        )
    }

    private var healthTile: some View {
        let summary = app.health.state.value
        return OrbitSummaryTile(
            title: "Movement", symbol: "figure.walk",
            value: summary?.steps.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
            detail: summary == nil ? "Open Apple Health" : summary?.steps == nil ? "No step sample" : "Steps recorded today",
            tint: AppTheme.success,
            action: { app.selectedTab = .health }
        )
    }

}

private struct HomeTaskRow: View {
    let item: TaskItem
    var isCompleting = false
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var showsCompletedState: Bool { item.isCompleted || isCompleting }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            TaskCompletionControl(
                title: item.title,
                isCompleted: item.isCompleted,
                isCompleting: isCompleting,
                idleColor: item.priority == .high ? AppTheme.coral : AppTheme.tertiaryText,
                iconFont: .title3,
                onToggle: onToggle
            )

            Button(action: onEdit) {
                HStack(spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(showsCompletedState ? AppTheme.tertiaryText : AppTheme.primaryText)
                            .strikethrough(showsCompletedState)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if hasMetadata {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                if item.isOverdue {
                                    Text("Overdue").foregroundStyle(AppTheme.destructive)
                                } else if let due = item.dueDate {
                                    Text(due.formatted(
                                        date: item.isDueToday ? .omitted : .abbreviated,
                                        time: .shortened
                                    ))
                                }
                                if item.source != .manual {
                                    if item.dueDate != nil { Text("·") }
                                    Text(item.source.label)
                                }
                                if item.priority == .high {
                                    Image(systemName: "exclamationmark")
                                }
                                if item.dueDate != nil, item.effectiveAlertStyle != .none {
                                    Image(systemName: item.effectiveAlertStyle == .alarm ? "alarm" : "bell")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .opacity(isCompleting ? 0.48 : 1)
            .accessibilityLabel("Edit \(item.title)")
        }
        .frame(minHeight: 76)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var hasMetadata: Bool {
        item.dueDate != nil || item.source != .manual || item.priority == .high
    }
}

private struct HomeFinanceMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.lg)
    }
}

struct CalendarHomeRow: View {
    let event: CalendarEvent
    var isInToDo = false
    /// The full timeline groups rows under day headers, so they omit the date.
    var showsDate = true
    let onAddToDo: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Refreshes "Starts in" and when Join appears without a reload.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            row(timing: EventTiming(event: event, now: context.date))
        }
        .cardRowPreviewSurface()
        .contextMenu {
            if let url = joinURL {
                Button { openURL(url) } label: {
                    Label("Join meeting", systemImage: "video")
                }
            } else if let url = event.meetingURL {
                Button { openURL(url) } label: {
                    Label("Open event link", systemImage: "safari")
                }
            }
            Button(action: onAddToDo) {
                Label(isInToDo ? "In your To Do" : "Add to To Do", systemImage: isInToDo ? "checkmark.circle" : "plus.circle")
            }
            .disabled(isInToDo)
            if let mapsURL {
                Button { openURL(mapsURL) } label: {
                    Label("Open in Maps", systemImage: "map")
                }
            }
        }
    }

    private func row(timing: EventTiming) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            timeColumn
                .frame(width: 62, alignment: .leading)

            Capsule()
                .fill(timing.isLive ? AppTheme.accent : AppTheme.separator)
                .frame(width: timing.isLive ? 3 : 1.5)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                if let status = timing.label {
                    Label(status, systemImage: timing.isLive ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.coral)
                } else {
                    Text(event.provider.label)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = joinURL, timing.canJoin {
                Button { openURL(url) } label: {
                    Text("Join")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(AppTheme.primaryButton, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(event.title)")
            } else {
                Button(action: onAddToDo) {
                    Image(systemName: isInToDo ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title3)
                        .foregroundStyle(isInToDo ? AppTheme.success : AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isInToDo)
                .accessibilityLabel(isInToDo ? "Already in To Do" : "Add \(event.title) to To Do")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, AppTheme.Spacing.md)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showsDate {
                Text(dayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .textCase(.uppercase)
            }
            if event.isAllDay {
                Text("All day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
            } else {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(event.isImportant ? AppTheme.coral : AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(event.start) { return "Today" }
        if Calendar.current.isDateInTomorrow(event.start) { return "Tomorrow" }
        return event.start.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Duration and place, e.g. "45 min · Room 4B".
    private var detailLine: String {
        var parts: [String] = []
        if !event.isAllDay, let end = event.end, end > event.start {
            parts.append(Duration.seconds(end.timeIntervalSince(event.start))
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    /// Providers also fill `meetingURL` with the event's own web page (Outlook)
    /// or any link on the event (Apple), so only video-call hosts get Join.
    private var joinURL: URL? {
        guard let url = event.meetingURL, let host = url.host?.lowercased() else { return nil }
        let meetingHosts = [
            "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
            "webex.com", "gotomeeting.com", "whereby.com", "chime.aws", "bluejeans.com", "facetime.apple.com"
        ]
        return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") } ? url : nil
    }

    /// A physical place, not a meeting link, that Maps can search for.
    private var mapsURL: URL? {
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty, !location.contains("://"),
              let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }
}

/// Where an event sits relative to now, for the Up next row.
private struct EventTiming {
    var isLive = false
    /// Set only in the hour before the event starts.
    var minutesUntilStart: Int?

    init(event: CalendarEvent, now: Date) {
        guard !event.isAllDay else { return }
        let end = event.end ?? event.start.addingTimeInterval(30 * 60)
        isLive = event.start <= now && now < end
        let untilStart = event.start.timeIntervalSince(now)
        if untilStart > 0, untilStart <= 60 * 60 {
            minutesUntilStart = max(1, Int((untilStart / 60).rounded(.up)))
        }
    }

    var label: String? {
        if isLive { return "Happening now" }
        return minutesUntilStart.map { "Starts in \($0) min" }
    }

    /// Join shows from 15 minutes before the start until the end.
    var canJoin: Bool { isLive || (minutesUntilStart ?? .max) <= 15 }
}

private struct CalendarTimelineView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if case let .loaded(events) = app.calendarState, !events.isEmpty {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg, pinnedViews: .sectionHeaders) {
                        ForEach(days(in: events)) { group in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                        CalendarHomeRow(
                                            event: event,
                                            isInToDo: tasks.tasks.contains { $0.relatedCalendarEventID == event.id },
                                            showsDate: false,
                                            onAddToDo: { app.addCalendarEventToTasks(event) }
                                        )
                                        if index < group.events.count - 1 {
                                            Divider().overlay(AppTheme.separator)
                                        }
                                    }
                                }
                                .cardSurface(padding: 0)
                            } header: {
                                dayHeader(group.day, count: group.events.count)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.page)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                } else {
                    InfoStateView(
                        systemImage: "calendar",
                        title: "No upcoming events",
                        message: "Your connected calendars are clear for the next 14 days."
                    )
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    /// Events keep their timeline order within each day.
    private func days(in events: [CalendarEvent]) -> [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { DayGroup(day: $0, events: grouped[$0] ?? []) }
    }

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayTitle(day))
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(count) event\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.xs)
        .background(AppTheme.background)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Shared rows

struct AttentionRow: View {
    let item: AttentionItem
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: item.category.systemImage)
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 30, height: 30)
                .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                Text(item.detail).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            ImportanceDot(importance: item.importance).padding(.top, 6)
        }
        .padding(AppTheme.Spacing.lg)
    }
}

struct InboxRow: View {
    let message: InboxMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.sender).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(message.receivedAt.relativeShort).font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            }
            Text(message.subject).font(.subheadline).foregroundStyle(AppTheme.primaryText).lineLimit(1)
            Text(message.aiSummary).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
            HStack(spacing: 4) {
                Image(systemName: message.provider.systemImage)
                Text(message.provider.label)
                Text("·")
                Text(message.mailboxEmail).lineLimit(1)
            }
            .font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            if message.actionRequired {
                Tag(text: "Action required", systemImage: "bolt", tint: AppTheme.primaryText).padding(.top, 2)
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
}

struct CompactJobRow: View {
    let job: JobApplication
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: job.status.systemImage).font(.footnote).foregroundStyle(job.status.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.company).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText).lineLimit(1)
                Text(job.status.rawValue).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(job.updatedAt.relativeShort).font(.caption2).foregroundStyle(AppTheme.tertiaryText)
        }
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

#Preview {
    let app = PreviewSupport.appState()
    return HomeView().environmentObject(app).environmentObject(app.inbox).environmentObject(app.tasks)
}

import SwiftData
import SwiftUI

/// The command center. Answers "what do I need to do right now?" with To Do as
/// the dominant first surface, followed by the rest of the day's context.
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @EnvironmentObject private var tasks: TaskRepository
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var showSettings = false
    @State private var showCalendar = false
    @State private var showHealth = false
    @State private var editingTask: TaskItem?
    @State private var placeholderIndex = 0

    private let placeholders = [
        "Anything important today?",
        "Did a recruiter email me?",
        "Who should I follow up with?",
        "What do I need to do today?"
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                        todoSection
                            .padding(AppTheme.Spacing.xl)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: min(max(360, viewport.size.height * 0.5), 480),
                                alignment: .topLeading
                            )
                            .background(
                                AppTheme.primarySurface,
                                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            }

                        attentionSection
                        todaySection
                        jobsSummary
                        inboxSummary
                        syncBanner
                        financeSummary
                        healthSummary
                        assistantSection
                    }
                    .padding(AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .background(AppTheme.background)
                .refreshable { await app.refreshDashboard() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { AppLogo(size: 26) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "person.crop.circle").font(.title3)
                        }
                        .tint(AppTheme.primaryText)
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showCalendar) { CalendarTimelineView() }
                .sheet(isPresented: $showHealth) { HealthView() }
                .sheet(item: $editingTask) { item in
                    TaskEditor(item: item) { saved in
                        if tasks.tasks.contains(where: { $0.id == saved.id }) {
                            tasks.update(saved)
                        } else {
                            tasks.add(saved)
                        }
                    }
                }
                .task {
                    await app.jobs.refresh()
                    if app.connections.calendarConnected { await app.refreshCalendar(presentErrors: false) }
                    if app.connections.healthConnected { await app.health.refresh() }
                    if app.finance.isBackendConfigured { await app.finance.load(showLoading: false) }
                }
            }
        }
    }

    // MARK: Greeting

    private var greeting: some View {
        Text("\(timeGreeting), \(app.user?.firstName ?? "there")")
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Ask Orbit")
            aiInput
        }
    }

    private var aiInput: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                app.assistantLaunch = .chat
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.brand)
                    Text(placeholders[placeholderIndex])
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .id(placeholderIndex)
                        .transition(.opacity)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().frame(height: 24)

            Button { app.assistantLaunch = .voice } label: {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.primarySurface, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk to Orbit")
        }
        .padding(.vertical, 5)
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation(.easeInOut) { placeholderIndex = (placeholderIndex + 1) % placeholders.count }
            }
        }
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("To Do")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    greeting
                    Text(todoSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button { editingTask = TaskItem(title: "") } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.onBrand)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.brand, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add To Do")
            }

            Divider().overlay(AppTheme.separator)

            if tasks.prioritizedOpen.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(AppTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing urgent")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("Add a task or scan email for suggested actions.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Button {
                        app.selectedTab = .tasks
                    } label: {
                        Label("Add your first task", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.prioritizedOpen.prefix(7).enumerated()), id: \.element.id) { index, task in
                        HomeTaskRow(
                            item: task,
                            onToggle: { tasks.toggle(task) },
                            onEdit: { editingTask = task }
                        )
                        if index < min(tasks.prioritizedOpen.count, 7) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
            }

            if !tasks.suggestions.isEmpty {
                Button {
                    app.selectedTab = .tasks
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.brand)
                        Text("\(tasks.suggestions.count) suggested action\(tasks.suggestions.count == 1 ? "" : "s") from email")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(AppTheme.Spacing.md)
                    .background(
                        AppTheme.secondarySurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Button("See all") {
                app.selectedTab = .tasks
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Jobs", actionTitle: "Open") { app.selectedTab = .jobs }
            VStack(spacing: 0) {
                metric("\(jobs.filter { !$0.isClosed }.count)", "Active applications")
                Divider().overlay(AppTheme.separator)
                metric("\(jobs.filter { $0.status == .interview || $0.status == .finalInterview }.count)", "Interviews")
                Divider().overlay(AppTheme.separator)
                metric("\(jobs.filter { [.applied, .screening, .recruiterContact].contains($0.status) }.count)", "Waiting for a response")
                Divider().overlay(AppTheme.separator)
                metric("\(attention.count)", "Follow-ups due")

                if let recent = jobs.prefix(3).map({ $0 }).nilIfEmpty {
                    Divider().overlay(AppTheme.separator)
                    Text("Recently updated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.lg)

                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, job in
                        CompactJobRow(job: job)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.vertical, AppTheme.Spacing.md)
                        if index < recent.count - 1 {
                            Divider().overlay(AppTheme.separator)
                                .padding(.leading, AppTheme.Spacing.lg)
                        }
                    }
                }
            }
            .cardSurface(padding: 0)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(AppTheme.Spacing.lg)
    }

    // MARK: Inbox summary

    private var inboxSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Inbox")
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
                        ForEach(messages.prefix(2)) { InboxRow(message: $0) }
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
                title: "Upcoming",
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
                    ForEach(Array(events.prefix(5).enumerated()), id: \.element.id) { index, event in
                        CalendarHomeRow(
                            event: event,
                            isInToDo: tasks.tasks.contains { $0.relatedCalendarEventID == event.id },
                            onAddToDo: { app.addCalendarEventToTasks(event) }
                        )
                        if index < min(events.count, 5) - 1 { Divider().overlay(AppTheme.separator) }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    // MARK: Finance + Health summaries

    @ViewBuilder
    private var financeSummary: some View {
        if case let .loaded(overview) = app.finance.state {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Finance", actionTitle: "View", action: { app.selectedTab = .finance })
                VStack(spacing: 0) {
                    HomeFinanceMetric(
                        title: "Cash",
                        value: overview.totalCash.formatted(
                            .currency(code: overview.currencyCode).precision(.fractionLength(0...2))
                        ),
                        tint: AppTheme.success
                    )
                    Divider().overlay(AppTheme.separator)
                    HomeFinanceMetric(
                        title: "Cards owed",
                        value: overview.totalCreditBalance.formatted(
                            .currency(code: overview.currencyCode).precision(.fractionLength(0...2))
                        ),
                        tint: AppTheme.coral
                    )
                    Divider().overlay(AppTheme.separator)
                    HomeFinanceMetric(
                        title: "Month net",
                        value: overview.monthlyNetFlow.formatted(
                            .currency(code: overview.currencyCode).precision(.fractionLength(0...2))
                        ),
                        tint: overview.monthlyNetFlow >= 0 ? AppTheme.success : AppTheme.coral
                    )
                }
                .cardSurface(padding: 0)
            }
        }
    }

    private var healthSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Health", actionTitle: "Details", action: { showHealth = true })
            switch app.health.state {
            case .loaded(let summary):
                VStack(spacing: 0) {
                    ForEach(Array(summary.metrics.prefix(4).enumerated()), id: \.element.id) { index, value in
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: value.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.brand)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.secondarySurface, in: Circle())
                            Text(value.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            Text(value.value)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(AppTheme.Spacing.lg)
                        if index < min(summary.metrics.count, 4) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            case .loading:
                LoadingStateView(message: "Loading Apple Health…").cardSurface()
            case .empty:
                InfoStateView(systemImage: "heart", title: "No recent health data",
                              message: "Orbit is connected, but the approved categories have no recent data.")
                    .cardSurface()
            case .failed(let message):
                InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load Health",
                              message: message, actionTitle: "Try again") { Task { await app.connectHealth() } }
                    .cardSurface()
            default:
                InfoStateView(systemImage: "heart", title: "Connect Apple Health",
                              message: "See your sleep, steps and workouts alongside everything else.",
                              actionTitle: "Connect Apple Health") { Task { await app.connectHealth() } }
                    .cardSurface()
            }
        }
    }
}

private struct HomeTaskRow: View {
    let item: TaskItem
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? AppTheme.success : AppTheme.brand)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            Button(action: onEdit) {
                HStack(spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.isCompleted ? AppTheme.tertiaryText : AppTheme.primaryText)
                            .strikethrough(item.isCompleted)
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
            .accessibilityLabel("Edit \(item.title)")
        }
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
    let onAddToDo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(spacing: 1) {
                Text(event.start, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.caption.weight(.bold)).foregroundStyle(event.isImportant ? AppTheme.brand : AppTheme.primaryText)
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText).lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                }
                Text(event.provider.label).font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer()
            Button(action: onAddToDo) {
                Image(systemName: isInToDo ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isInToDo ? AppTheme.success : AppTheme.primaryText)
            }
            .buttonStyle(.plain)
            .disabled(isInToDo)
            .accessibilityLabel(isInToDo ? "Already in To Do" : "Add to To Do")
        }
        .padding(AppTheme.Spacing.lg)
    }
}

private struct CalendarTimelineView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if case let .loaded(events) = app.calendarState {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            CalendarHomeRow(
                                event: event,
                                isInToDo: tasks.tasks.contains { $0.relatedCalendarEventID == event.id },
                                onAddToDo: { app.addCalendarEventToTasks(event) }
                            )
                            if index < events.count - 1 { Divider().overlay(AppTheme.separator) }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
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

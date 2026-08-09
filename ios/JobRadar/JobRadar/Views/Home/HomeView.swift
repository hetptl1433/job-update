import SwiftData
import SwiftUI

/// The command center. Answers "what do I need to know or do right now?" — not
/// an analytics dashboard. Hierarchy: attention → what changed → what's next → ask AI.
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @State private var assistantPrompt = ""
    @State private var openAssistant = false
    @State private var showSettings = false
    @State private var placeholderIndex = 0

    private let placeholders = [
        "Anything important today?",
        "Did a recruiter email me?",
        "Who should I follow up with?",
        "What do I need to do today?"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    greeting
                    aiInput
                    attentionSection
                    jobsSummary
                    inboxSummary
                    todaySection
                    healthSummary
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AppLogo(size: 26) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle").font(.title3)
                    }
                    .tint(AppTheme.primaryText)
                }
            }
            .navigationDestination(isPresented: $openAssistant) {
                AssistantView(initialPrompt: assistantPrompt)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                await app.jobs.refresh()
                await app.inbox.refresh()
            }
        }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeGreeting + ",")
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
            Text(app.user?.firstName ?? "there")
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: AI input

    private var aiInput: some View {
        Button {
            assistantPrompt = ""
            openAssistant = true
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.primaryText)
                Text(placeholders[placeholderIndex])
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .id(placeholderIndex)
                    .transition(.opacity)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(AppTheme.primaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation(.easeInOut) { placeholderIndex = (placeholderIndex + 1) % placeholders.count }
            }
        }
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
            if attention.isEmpty {
                InfoStateView(
                    systemImage: "checkmark.circle",
                    title: "You're all caught up",
                    message: app.connections.gmailConnected
                        ? "Nothing needs your attention right now."
                        : "Connect Gmail and Calendar to surface what needs you."
                )
                .cardSurface()
            } else {
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
            SectionHeader(title: "Jobs")
            VStack(spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.xl) {
                    metric("\(jobs.filter { !$0.isClosed }.count)", "Active")
                    metric("\(jobs.filter { $0.status == .interview || $0.status == .finalInterview }.count)", "Interviews")
                    metric("\(jobs.filter { [.applied, .screening, .recruiterContact].contains($0.status) }.count)", "Waiting")
                    metric("\(attention.count)", "Follow-ups")
                }
                if let recent = jobs.prefix(3).map({ $0 }).nilIfEmpty {
                    Divider().overlay(AppTheme.separator)
                    ForEach(recent) { job in CompactJobRow(job: job) }
                }
            }
            .cardSurface()
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(AppTheme.primaryText)
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Inbox summary

    private var inboxSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Inbox")
            Group {
                switch app.inbox.state {
                case .disconnected:
                    InfoStateView(systemImage: "envelope", title: "Gmail not connected",
                                  message: "Connect Gmail to see messages that need your attention.",
                                  actionTitle: "Connect Gmail") { Task { await app.connectGmail() } }
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
            .cardSurface(padding: app.inbox.state.value == nil ? AppTheme.Spacing.lg : 0)
        }
    }

    // MARK: Today / calendar

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Today")
            if app.connections.calendarConnected {
                InfoStateView(systemImage: "calendar", title: "No events loaded",
                              message: "Calendar sync will appear here once the backend is connected.")
                    .cardSurface()
            } else {
                InfoStateView(systemImage: "calendar", title: "Calendar not connected",
                              message: "Connect Calendar to see interviews, meetings and deadlines.",
                              actionTitle: "Connect Calendar") { Task { await app.connectCalendar() } }
                    .cardSurface()
            }
        }
    }

    // MARK: Health summary

    private var healthSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Health")
            InfoStateView(systemImage: "heart", title: "Connect Apple Health",
                          message: "See your sleep, steps and workouts alongside everything else.",
                          actionTitle: "Connect Apple Health") { app.connectHealth() }
                .cardSurface()
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
    HomeView().environmentObject(PreviewSupport.appState())
}

import SwiftData
import SwiftUI

/// The application tracker. Typography- and icon-led with restrained color.
/// The "Sync from email" action pulls connected inboxes, lets ChatGPT extract job activity,
/// and proposes updates the user accepts (never silent writes).
struct JobsView: View {
    @EnvironmentObject private var app: AppState
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var applications: [JobApplication]

    @State private var searchText = ""
    @State private var editing: JobApplication?
    @State private var newApplication: JobApplication?
    @State private var filter: JobFilter = .active
    @State private var showsAll = false
    @State private var pendingDeletion: JobApplication?
    /// Deleted once the editor that asked for it has finished dismissing.
    @State private var deleteAfterEditorDismisses: JobApplication?
    @State private var statusFeedback = 0
    @Environment(\.orbitWideLayout) private var isWide
    @Environment(\.openURL) private var openURL

    /// Until expanded, the list shows the latest few. A wide iPad has room for more.
    private var recentLimit: Int { isWide ? 10 : 5 }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesQuery(_ job: JobApplication) -> Bool {
        query.isEmpty || [job.company, job.role, job.location, job.recruiterName, job.status.rawValue]
            .joined(separator: " ").lowercased().contains(query)
    }

    /// Newest first, from the `@Query` sort.
    private var filtered: [JobApplication] {
        applications.filter { filter.includes($0.status) && matchesQuery($0) }
    }

    /// Search results are never truncated.
    private var visible: [JobApplication] {
        showsAll || !query.isEmpty ? filtered : Array(filtered.prefix(recentLimit))
    }

    /// Search matches that the selected filter hides.
    private var matchesInOtherFilters: Int {
        guard !query.isEmpty, filter != .all else { return 0 }
        return applications.filter(matchesQuery).count - filtered.count
    }

    private var attentionJobs: [JobApplication] {
        let stale = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return applications.filter { job in
            guard job.status.isActive else { return false }
            if let due = job.nextActionDate, due <= .now { return true }
            return job.updatedAt < stale && !job.status.isOffer
        }
        .sorted { ($0.nextActionDate ?? $0.updatedAt) < ($1.nextActionDate ?? $1.updatedAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                OrbitColumns(spacing: AppTheme.Spacing.md) {
                    OrbitPageHeading(
                        title: "Jobs",
                        subtitle: "Your next chapter, moving forward.",
                        actionTitle: "Add an opportunity",
                        action: { newApplication = JobApplication() }
                    )
                    .padding(.bottom, AppTheme.Spacing.sm)
                    VStack(spacing: AppTheme.Spacing.md) {
                        dashboardSummary
                        Button {
                            Task { await app.syncEmail() }
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                if app.isSyncing { ProgressView().controlSize(.small) }
                                else { Image(systemName: "sparkles") }
                                Text(app.isSyncing ? (app.syncStageMessage ?? "Scanning email…") : "Scan email for updates")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.coral)
                            .frame(minHeight: 44)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(app.isSyncing)
                    }
                    .orbitColumn(.leading)
                    if !attentionJobs.isEmpty { needsAttention.orbitColumn(.shorter) }
                    if !app.detectedJobUpdates.isEmpty { detectedSection.orbitColumn(.shorter) }

                    if applications.isEmpty && app.detectedJobUpdates.isEmpty {
                        InfoStateView(systemImage: "briefcase", title: "No applications yet",
                                      message: "Add one manually, or sync your email to detect job activity automatically.",
                                      actionTitle: "Scan email") { Task { await app.syncEmail() } }
                            .padding(.top, AppTheme.Spacing.xl)
                    } else {
                        applicationList.orbitColumn(.shorter)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.background)
            .orbitNavigationChrome()
            .searchable(text: $searchText, prompt: "Company, role, or recruiter")
            .refreshable { await app.refreshJobs() }
            .sheet(item: $editing, onDismiss: deleteIfRequestedFromEditor) { job in
                JobEditor(
                    job: job,
                    isNew: false,
                    onSave: { app.jobs.touch(job) },
                    onDelete: {
                        deleteAfterEditorDismisses = job
                        editing = nil
                    }
                )
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { job in
                Button("Delete Application", role: .destructive) {
                    pendingDeletion = nil
                    withAnimation(.easeOut(duration: 0.2)) { app.jobs.delete(job) }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("This removes it from your tracker and cancels its follow-up reminder. This can't be undone.")
            }
            .sensoryFeedback(.selection, trigger: statusFeedback)
            // The draft lives in state so a refresh while the sheet is open
            // can't replace it with a blank one.
            .sheet(item: $newApplication) { draft in
                JobEditor(job: draft, isNew: true) {
                    app.jobs.add(draft)
                }
            }
            .task { await app.jobs.refreshIfStale() }
        }
    }

    private var dashboardSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Grid(horizontalSpacing: AppTheme.Spacing.lg, verticalSpacing: AppTheme.Spacing.md) {
                GridRow {
                    summaryMetric("Active", applications.filter { $0.status.isActive }.count)
                    summaryMetric("Interview", applications.filter { $0.status == .interview || $0.status == .finalInterview }.count)
                    summaryMetric("Offers", applications.filter { $0.status.isOffer }.count)
                }
                Divider().gridCellColumns(3).overlay(AppTheme.separator)
                GridRow {
                    summaryMetric("Waiting", applications.filter { [.applied, .screening, .recruiterContact].contains($0.status) }.count)
                    summaryMetric("Follow-up", attentionJobs.count)
                    summaryMetric("Rejected", applications.filter { $0.status == .rejected }.count)
                }
            }
        }
        .cardSurface()
    }

    private func summaryMetric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title.weight(.medium)).tracking(-0.8).monospacedDigit().foregroundStyle(AppTheme.primaryText)
            Text(label.uppercased()).font(.caption2).tracking(0.6).foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var needsAttention: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Needs attention")
            VStack(spacing: 0) {
                ForEach(Array(attentionJobs.prefix(4).enumerated()), id: \.element.id) { index, job in
                    Button { editing = job } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.company).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                                Text(attentionReason(job)).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                        }
                        .padding(AppTheme.Spacing.md)
                        .cardRowPreviewSurface()
                    }
                    .buttonStyle(.plain)
                    .contextMenu { jobActions(job) }
                    if index < min(attentionJobs.count, 4) - 1 { Divider().overlay(AppTheme.separator) }
                }
            }
            .cardSurface(padding: 0)
        }
    }

    private func attentionReason(_ job: JobApplication) -> String {
        if let due = job.nextActionDate, due <= .now {
            return job.nextAction.isEmpty ? "Follow-up is due" : job.nextAction
        }
        let days = max(7, Calendar.current.dateComponents([.day], from: job.updatedAt, to: .now).day ?? 7)
        return "No activity for \(days) days"
    }

    // MARK: Applications

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: listTitle)
            filterChips

            if visible.isEmpty {
                emptyListState.cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, job in
                        Button { editing = job } label: {
                            JobRow(job: job)
                                .padding(.horizontal, AppTheme.Spacing.lg)
                                .cardRowPreviewSurface()
                        }
                        .buttonStyle(.plain)
                        .contextMenu { jobActions(job) }
                        .accessibilityHint("Opens details. Touch and hold for more actions.")
                        if index < visible.count - 1 {
                            Divider().overlay(AppTheme.separator).padding(.horizontal, AppTheme.Spacing.lg)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }

            if visible.count < filtered.count {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsAll = true }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text("Show all \(filtered.count)")
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var listTitle: String {
        if !query.isEmpty {
            return "\(filtered.count) result\(filtered.count == 1 ? "" : "s")"
        }
        if visible.count < filtered.count {
            return "\(filter.listTitle) · Latest \(visible.count)"
        }
        return filter.listTitle
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(JobFilter.allCases) { option in
                    JobFilterChip(
                        title: option.title,
                        count: applications.filter { option.includes($0.status) }.count,
                        isSelected: filter == option
                    ) {
                        guard filter != option else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            filter = option
                            showsAll = false
                        }
                        statusFeedback += 1
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var emptyListState: some View {
        if matchesInOtherFilters > 0 {
            InfoStateView(
                systemImage: "magnifyingglass",
                title: "Nothing in \(filter.title)",
                message: "\(matchesInOtherFilters) other application\(matchesInOtherFilters == 1 ? " matches" : "s match") “\(searchText)”.",
                actionTitle: "Search all applications"
            ) {
                withAnimation(.easeOut(duration: 0.18)) { filter = .all }
            }
        } else if !query.isEmpty {
            InfoStateView(
                systemImage: "magnifyingglass",
                title: "No matching applications",
                message: "Try a different company, role, or recruiter."
            )
        } else if applications.isEmpty {
            InfoStateView(
                systemImage: "briefcase",
                title: "No applications yet",
                message: "Review the updates found in your email, or add one with +."
            )
        } else if filter == .active {
            InfoStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No active applications",
                message: "Closed applications stay in your totals but do not clutter this list."
            )
        } else {
            InfoStateView(
                systemImage: "tray",
                title: "Nothing in \(filter.title) yet",
                message: "Applications appear here as they move through your pipeline."
            )
        }
    }

    @ViewBuilder
    private func jobActions(_ job: JobApplication) -> some View {
        Button { editing = job } label: {
            Label("Edit", systemImage: "pencil")
        }
        Picker(selection: Binding(get: { job.status }, set: { setStatus($0, for: job) })) {
            ForEach(JobStatus.allCases) { status in
                Label(status.rawValue, systemImage: status.systemImage).tag(status)
            }
        } label: {
            Label("Move to", systemImage: "arrow.right.circle")
        }
        .pickerStyle(.menu)
        if let url = job.postingURL {
            Button { openURL(url) } label: {
                Label("Open job posting", systemImage: "safari")
            }
        }
        if !job.recruiterEmail.isEmpty {
            Button { UIPasteboard.general.string = job.recruiterEmail } label: {
                Label("Copy recruiter email", systemImage: "doc.on.doc")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDeletion = job } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func setStatus(_ status: JobStatus, for job: JobApplication) {
        guard job.status != status else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            job.status = status
            app.jobs.touch(job)
        }
        statusFeedback += 1
    }

    private var deletionTitle: String {
        guard let company = pendingDeletion?.company, !company.isEmpty else { return "Delete this application?" }
        return "Delete \(company)?"
    }

    private func deleteIfRequestedFromEditor() {
        guard let job = deleteAfterEditorDismisses else { return }
        deleteAfterEditorDismisses = nil
        withAnimation(.easeOut(duration: 0.2)) { app.jobs.delete(job) }
    }

    private var syncButton: some View {
        Button {
            Task { await app.syncEmail() }
        } label: {
            if app.isSyncing {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .tint(AppTheme.brand)
        .disabled(app.isSyncing)
        .accessibilityLabel("Scan connected email for job updates")
    }

    // MARK: Detected updates

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.brand)
                Text("Detected from email").sectionLabel()
                Spacer()
                if let summary = app.lastSyncSummary {
                    Text(summary).font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                }
            }
            Text("Review before changing your tracker.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(app.detectedJobUpdates) { update in
                DetectedUpdateCard(
                    update: update,
                    onAccept: { app.acceptJobUpdate(update) },
                    onDismiss: { app.dismissJobUpdate(update) }
                )
            }
        }
    }

}

// MARK: - Detected update card

struct DetectedUpdateCard: View {
    let update: DetectedJobUpdate
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: update.status.systemImage).foregroundStyle(update.status.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(update.company).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                    Text(update.role.isEmpty ? update.status.rawValue : "\(update.role) · \(update.status.rawValue)")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Tag(text: update.status.rawValue, tint: update.status.tint)
            }
            if !update.reason.isEmpty {
                Text(update.reason).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
            }
            if !update.nextAction.isEmpty {
                Label(update.nextAction, systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(update.sourceSubject).lineLimit(1)
                HStack(spacing: 4) {
                    Text(update.sourceProvider.label)
                    Text("·")
                    Text(update.sourceMailbox)
                    if let date = update.sourceDate {
                        Text("·")
                        Text(date.relativeShort)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.tertiaryText)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(action: onAccept) {
                    Label("Update", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(AppTheme.primaryButton, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update \(update.company) in your tracker")
                Button(action: onDismiss) {
                    Text("Ignore")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(AppTheme.secondarySurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ignore update for \(update.company)")
                Spacer()
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.separator) }
    }
}

// MARK: - Row

struct JobRow: View {
    let job: JobApplication

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Text(job.initials.isEmpty ? "—" : job.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(job.status.tint)
                    .frame(width: 42, height: 42)
                    .background(job.status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.company).font(.headline).foregroundStyle(AppTheme.primaryText).lineLimit(1)
                    Text(job.position.isEmpty ? "—" : job.position)
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Tag(text: job.status.rawValue, systemImage: job.status.systemImage, tint: job.status.tint)
            }
            if !job.nextAction.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2)
                    Text(job.nextAction).font(.caption).lineLimit(2)
                }
                .foregroundStyle(AppTheme.secondaryText)
            }
            if let due = job.nextActionDate {
                Label(
                    isFollowUpDue(due) ? "Follow up · \(due.formatted(date: .abbreviated, time: .omitted))" : due.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "bell"
                )
                .font(.caption2)
                .foregroundStyle(isFollowUpDue(due) ? AppTheme.coral : AppTheme.tertiaryText)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func isFollowUpDue(_ date: Date) -> Bool {
        job.status.isActive && Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now)
    }
}

// MARK: - Filters

private enum JobFilter: String, CaseIterable, Identifiable {
    case active, interview, offers, waiting, closed, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .interview: "Interview"
        case .offers: "Offers"
        case .waiting: "Waiting"
        case .closed: "Closed"
        case .all: "All"
        }
    }

    var listTitle: String {
        switch self {
        case .active: "Active applications"
        case .interview: "Interviewing"
        case .offers: "Offers"
        case .waiting: "Waiting to hear back"
        case .closed: "Closed applications"
        case .all: "All applications"
        }
    }

    /// Mirrors the summary metrics so a chip's count matches its tile.
    func includes(_ status: JobStatus) -> Bool {
        switch self {
        case .active: status.isActive
        case .interview: status == .interview || status == .finalInterview
        case .offers: status.isOffer
        case .waiting: [.applied, .screening, .recruiterContact].contains(status)
        case .closed: status.isClosed
        case .all: true
        }
    }
}

private struct JobFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppTheme.coral.opacity(0.8) : AppTheme.tertiaryText)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? AppTheme.coral : AppTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(isSelected ? AppTheme.accent.opacity(0.14) : AppTheme.secondarySurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? AppTheme.accent.opacity(0.5) : AppTheme.border, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) application\(count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension JobApplication {
    /// The saved posting link, if it's a web address Orbit can open.
    var postingURL: URL? {
        let text = jobURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

// MARK: - Editor

struct JobEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var job: JobApplication
    let isNew: Bool
    let onSave: () -> Void
    /// Offered for saved applications. The caller deletes after dismissal.
    var onDelete: (() -> Void)? = nil
    @State private var didSave = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Company") {
                    TextField("Company", text: $job.company)
                    TextField("Position", text: $job.position)
                    TextField("Location", text: $job.location)
                }
                Section("Pipeline") {
                    Picker("Status", selection: Binding(get: { job.status }, set: { job.status = $0 })) {
                        ForEach(JobStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Priority", selection: Binding(get: { job.priority }, set: { job.priority = $0 })) {
                        ForEach(JobPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    TextField("What's next?", text: $job.nextAction, axis: .vertical).lineLimit(2...5)
                    Toggle("Follow-up reminder", isOn: Binding(
                        get: { job.nextActionDate != nil },
                        set: { enabled in
                            job.nextActionDate = enabled ? (job.nextActionDate ?? Self.defaultFollowUp) : nil
                        }
                    ))
                    if job.nextActionDate != nil {
                        DatePicker("Follow up on", selection: Binding(
                            get: { job.nextActionDate ?? Self.defaultFollowUp },
                            set: { job.nextActionDate = $0 }), displayedComponents: .date)
                    }
                } header: {
                    Text("Next action")
                } footer: {
                    if job.nextActionDate != nil, job.status.isActive {
                        Text("Orbit reminds you at 9 AM that day.")
                    }
                }
                Section("Recruiter") {
                    TextField("Name", text: $job.recruiterName)
                    TextField("Email", text: $job.recruiterEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Source", text: $job.source)
                    TextField("Job URL", text: $job.jobURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    if let url = job.postingURL {
                        Button { openURL(url) } label: {
                            Label("Open job posting", systemImage: "safari")
                        }
                    }
                    TextField("Notes", text: $job.notes, axis: .vertical).lineLimit(2...6)
                }
                if !isNew, onDelete != nil {
                    Section {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete application", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add application" : job.company)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        didSave = true
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete \(job.company.isEmpty ? "this application" : job.company)?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Application", role: .destructive) { onDelete?() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it from your tracker and cancels its follow-up reminder. This can't be undone.")
            }
        }
        // The form edits the stored application directly, so leaving without
        // Save (Cancel, swipe down, or Delete) puts back what was saved.
        .onDisappear {
            if !isNew, !didSave { job.modelContext?.rollback() }
        }
    }

    private static var defaultFollowUp: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}

#Preview {
    JobsView()
        .environmentObject(PreviewSupport.appState())
        .modelContainer(PreviewSupport.container)
}

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
    @State private var adding = false

    private var recentActive: [JobApplication] {
        applications
            .filter { job in
                guard job.status.isActive else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return query.isEmpty ||
                [job.company, job.role, job.status.rawValue].joined(separator: " ").lowercased().contains(query)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { $0 }
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
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    dashboardSummary
                    if !attentionJobs.isEmpty { needsAttention }
                    if !app.detectedJobUpdates.isEmpty { detectedSection }

                    if applications.isEmpty && app.detectedJobUpdates.isEmpty {
                        InfoStateView(systemImage: "briefcase", title: "No applications yet",
                                      message: "Add one manually, or sync your email to detect job activity automatically.",
                                      actionTitle: "Scan email") { Task { await app.syncEmail() } }
                            .padding(.top, AppTheme.Spacing.xl)
                    } else {
                        SectionHeader(title: "Recent active · Latest 5")
                        VStack(spacing: 0) {
                            ForEach(Array(recentActive.enumerated()), id: \.element.id) { index, job in
                                Button { editing = job } label: { JobRow(job: job) }
                                    .buttonStyle(.plain)
                                if index < recentActive.count - 1 { Divider().overlay(AppTheme.separator) }
                            }
                        }
                        if recentActive.isEmpty && !applications.isEmpty {
                            InfoStateView(systemImage: "line.3.horizontal.decrease.circle",
                                          title: "No active applications", message: "Closed applications stay in your totals but do not clutter this list.")
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Jobs")
            .searchable(text: $searchText, prompt: "Company or role")
            .refreshable { await app.refreshJobs() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { syncButton }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                    .tint(AppTheme.primaryText)
                }
            }
            .sheet(item: $editing) { job in
                JobEditor(job: job, isNew: false) { app.jobs.touch(job) }
            }
            .sheet(isPresented: $adding) {
                let draft = JobApplication()
                JobEditor(job: draft, isNew: true) {
                    app.jobs.add(draft)
                }
            }
            .task { await app.jobs.refresh() }
        }
    }

    private var dashboardSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("\(applications.count) Application\(applications.count == 1 ? "" : "s")")
                .font(.title2.weight(.bold)).foregroundStyle(AppTheme.primaryText)
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
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    private func summaryMetric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(AppTheme.primaryText)
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
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
                        .padding(.vertical, AppTheme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    if index < min(attentionJobs.count, 4) - 1 { Divider().overlay(AppTheme.separator) }
                }
            }
        }
    }

    private func attentionReason(_ job: JobApplication) -> String {
        if let due = job.nextActionDate, due <= .now {
            return job.nextAction.isEmpty ? "Follow-up is due" : job.nextAction
        }
        let days = max(7, Calendar.current.dateComponents([.day], from: job.updatedAt, to: .now).day ?? 7)
        return "No activity for \(days) days"
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
            HStack(spacing: AppTheme.Spacing.md) {
                Button(action: onAccept) {
                    Label("Update", systemImage: "checkmark.circle")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                Button("Ignore", action: onDismiss)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .buttonStyle(.plain)
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
                Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "bell")
                    .font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

// MARK: - Editor

struct JobEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: JobApplication
    let isNew: Bool
    let onSave: () -> Void

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
                Section("Next action") {
                    TextField("What's next?", text: $job.nextAction, axis: .vertical).lineLimit(2...5)
                    DatePicker("Follow-up", selection: Binding(
                        get: { job.nextActionDate ?? .now },
                        set: { job.nextActionDate = $0 }), displayedComponents: .date)
                }
                Section("Recruiter") {
                    TextField("Name", text: $job.recruiterName)
                    TextField("Email", text: $job.recruiterEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Source", text: $job.source)
                    TextField("Job URL", text: $job.jobURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Notes", text: $job.notes, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle(isNew ? "Add application" : job.company)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    JobsView()
        .environmentObject(PreviewSupport.appState())
        .modelContainer(PreviewSupport.container)
}

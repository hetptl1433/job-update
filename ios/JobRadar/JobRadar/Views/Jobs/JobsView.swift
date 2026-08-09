import SwiftData
import SwiftUI

/// The application tracker. Replaces the old Radar screen. Typography- and
/// icon-led; status uses restrained semantic indicators, not rainbow colors.
struct JobsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", active = "Active", interviews = "Interviews", offers = "Offers", closed = "Closed"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var applications: [JobApplication]

    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var editing: JobApplication?
    @State private var adding = false

    private var visible: [JobApplication] {
        applications.filter { job in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .active: !job.isClosed
            case .interviews: job.status == .interview || job.status == .finalInterview
            case .offers: job.status.isOffer
            case .closed: job.isClosed
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty ||
                [job.company, job.role, job.status.rawValue].joined(separator: " ").lowercased().contains(query)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if applications.isEmpty {
                    InfoStateView(systemImage: "briefcase", title: "No applications yet",
                                  message: "Add your first application to start tracking.",
                                  actionTitle: "Add application") { adding = true }
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppTheme.Spacing.md) {
                            filters
                            ForEach(visible) { job in
                                Button { editing = job } label: { JobRow(job: job) }
                                    .buttonStyle(.plain)
                            }
                            if visible.isEmpty {
                                InfoStateView(systemImage: "line.3.horizontal.decrease.circle",
                                              title: "Nothing here", message: "Try a different filter or search.")
                            }
                        }
                        .padding(AppTheme.Spacing.lg)
                    }
                    .searchable(text: $searchText, prompt: "Company or role")
                    .refreshable { await app.jobs.refresh() }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .tint(AppTheme.primaryText)
                }
            }
            .sheet(item: $editing) { job in
                JobEditor(job: job, isNew: false) {
                    app.jobs.touch(job)
                }
            }
            .sheet(isPresented: $adding) {
                let draft = JobApplication()
                JobEditor(job: draft, isNew: true) {
                    context.insert(draft)
                    try? context.save()
                }
            }
            .task { await app.jobs.refresh() }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(Filter.allCases) { value in
                    let selected = filter == value
                    Button(value.rawValue) { withAnimation(.snappy) { filter = value } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? AppTheme.onAccent : AppTheme.primaryText)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(selected ? AppTheme.accent : AppTheme.secondarySurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: selected ? 0 : 1))
                }
            }
        }
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
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
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
        .cardSurface()
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

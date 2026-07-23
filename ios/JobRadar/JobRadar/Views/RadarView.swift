import SwiftData
import SwiftUI

struct RadarView: View {
    enum Filter: String, CaseIterable, Identifiable { case all = "All", active = "Active", action = "Needs action", offers = "Offers", closed = "Closed"; var id: String { rawValue } }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query(sort: [SortDescriptor(\JobApplication.followUpDate), SortDescriptor(\JobApplication.updatedAt, order: .reverse)]) private var applications: [JobApplication]
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var editing: JobApplication?
    @State private var adding = false

    private var visible: [JobApplication] {
        applications.filter { item in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .active: !item.isClosed && item.status != .needsUpdate
            case .action: item.status == .needsUpdate || isDue(item.followUpDate)
            case .offers: item.status.isOffer
            case .closed: item.isClosed
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty || [item.company, item.role, item.statusRaw].joined(separator: " ").lowercased().contains(query)
            return matchesFilter && matchesSearch
        }
    }

    private var actionCount: Int { applications.filter { $0.status == .needsUpdate || isDue($0.followUpDate) }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.radarCanvas.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        RadarHeader(actionCount: actionCount, total: applications.count, active: applications.filter { !$0.isClosed }.count, syncState: session.syncState)
                        filters
                        if visible.isEmpty { emptyState.padding(.top, 70) }
                        else {
                            LazyVStack(spacing: 12) {
                                ForEach(visible) { application in
                                    ApplicationCard(application: application).onTapGesture { editing = application }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100)
                        }
                    }
                }
                .refreshable { _ = await session.refresh(using: context) }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Company or role")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus").fontWeight(.bold) }
                }
            }
            .sheet(item: $editing) { ApplicationEditor(application: $0) }
            .sheet(isPresented: $adding) { NewApplicationView() }
            .alert("Job Radar", isPresented: Binding(get: { session.alertMessage != nil }, set: { if !$0 { session.alertMessage = nil } })) {
                Button("OK", role: .cancel) { session.alertMessage = nil }
            } message: { Text(session.alertMessage ?? "") }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { value in
                    Button(value.rawValue) { withAnimation(.snappy) { filter = value } }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(filter == value ? Color.radarInk : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(filter == value ? Color.radarMint : Color.white, in: Capsule())
                }
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            RadarPulse().frame(width: 66, height: 66)
            Text("Nothing on this frequency").font(.title3.bold())
            Text("Change the filter or add a company.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func isDue(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now)
    }
}

private struct RadarHeader: View {
    let actionCount: Int
    let total: Int
    let active: Int
    let syncState: AppSession.SyncState

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.radarInk, .radarNight], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { proxy in
                ZStack {
                    ForEach([0.34, 0.54, 0.78], id: \.self) { scale in
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: proxy.size.width * scale)
                    }
                    Rectangle().fill(LinearGradient(colors: [.radarMint.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)).frame(width: proxy.size.width * 0.42, height: 1).rotationEffect(.degrees(-24))
                    RadarPulse().frame(width: 28, height: 28).offset(x: 48, y: -24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).offset(x: proxy.size.width * 0.28)
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HET'S SEARCH").font(.caption2.weight(.black)).tracking(1.8).foregroundStyle(.radarMint)
                        Text("Job radar").font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                    Label(syncLabel, systemImage: "circle.fill").font(.caption2.bold()).foregroundStyle(.white.opacity(0.75))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(actionCount)").font(.system(size: 58, weight: .black, design: .rounded)).foregroundStyle(actionCount > 0 ? .radarAmber : .radarMint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(actionCount == 1 ? "item needs" : "items need").font(.headline).foregroundStyle(.white)
                        Text("your attention").font(.headline).foregroundStyle(.white.opacity(0.62))
                    }
                }
                HStack(spacing: 22) {
                    stat("\(active)", "active")
                    stat("\(total)", "tracked")
                    stat("6 AM", "daily scan")
                }
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
        }
        .frame(height: 250)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
    }

    private var syncLabel: String {
        switch syncState { case .syncing: "SCANNING"; case .synced: "CURRENT"; case .offline: "OFFLINE"; case .failed(_): "CHECK"; case .idle: "READY" }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.headline.bold()).foregroundStyle(.white); Text(label.uppercased()).font(.system(size: 9, weight: .black)).tracking(1).foregroundStyle(.white.opacity(0.45)) }
    }
}

private struct ApplicationCard: View {
    let application: JobApplication

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(application.status.color.opacity(0.13))
                    Text(initials).font(.caption.weight(.black)).foregroundStyle(application.status.color)
                }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.company).font(.headline.weight(.black)).lineLimit(1)
                    Text(application.role).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(application.status.compactTitle.uppercased())
                    .font(.system(size: 9, weight: .black)).tracking(0.7)
                    .foregroundStyle(application.status.color)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(application.status.color.opacity(0.11), in: Capsule())
            }
            if !application.nextAction.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXT MOVE").font(.system(size: 9, weight: .black)).tracking(1.1).foregroundStyle(.secondary)
                    Text(application.nextAction).font(.subheadline.weight(.semibold)).lineLimit(3)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.radarCanvas, in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 8) {
                Label(application.stage, systemImage: "point.3.connected.trianglepath.dotted").lineLimit(1)
                Spacer()
                if let due = application.followUpDate { Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "bell") }
            }.font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .leading) { Capsule().fill(application.status.color).frame(width: 4).padding(.vertical, 18) }
        .shadow(color: Color.radarInk.opacity(0.06), radius: 14, y: 7)
    }

    private var initials: String { application.company.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
}

private struct NewApplicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var application = JobApplication()
    var body: some View { NavigationStack { ApplicationForm(application: application, isNew: true) { context.insert(application); try? context.save(); dismiss() }.navigationTitle("Add company").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
}

private struct ApplicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var application: JobApplication
    var body: some View { NavigationStack { ApplicationForm(application: application, isNew: false) { application.updatedAt = .now; try? context.save(); Task { await NotificationManager.shared.scheduleReminder(for: JobApplicationDTO(model: application)) }; dismiss() }.navigationTitle(application.company).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } } }
}

private struct ApplicationForm: View {
    @Bindable var application: JobApplication
    let isNew: Bool
    let save: () -> Void
    var body: some View {
        Form {
            Section("Company") { TextField("Company", text: $application.company); TextField("Role", text: $application.role) }
            Section("Pipeline") {
                Picker("Status", selection: Binding(get: { application.status }, set: { application.status = $0 })) { ForEach(JobStatus.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Priority", selection: Binding(get: { application.priority }, set: { application.priority = $0 })) { ForEach(JobPriority.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Stage", text: $application.stage)
            }
            Section("Action") {
                TextField("Next action", text: $application.nextAction, axis: .vertical).lineLimit(2...5)
                DatePicker("Follow-up", selection: Binding(get: { application.followUpDate ?? .now }, set: { application.followUpDate = $0 }), displayedComponents: .date)
            }
            Section("Details") { TextField("Recruiter", text: $application.contact); TextField("Mode / location", text: $application.mode); TextField("Notes", text: $application.notes, axis: .vertical).lineLimit(2...6) }
            Button(isNew ? "Add to radar" : "Save changes", action: save).frame(maxWidth: .infinity).fontWeight(.bold)
        }
    }
}

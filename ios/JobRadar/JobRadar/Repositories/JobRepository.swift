import Foundation
import SwiftData

/// Owns synchronization between the local SwiftData store and the backend job
/// tracker. Views read the list reactively via `@Query`; this type handles
/// refresh, save, and mutation with an audit-friendly update path.
@MainActor
final class JobRepository: ObservableObject {
    enum SyncState: Equatable { case idle, syncing, synced, failed(String) }

    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var lastSync: Date?

    private let api: APIClient
    private let context: ModelContext

    init(api: APIClient, context: ModelContext) {
        self.api = api
        self.context = context
    }

    @discardableResult
    func refresh() async -> Bool {
        syncState = .syncing
        do {
            let remote = try await api.fetchApplications()
            try upsert(remote)
            lastSync = .now
            syncState = .synced
            await NotificationManager.shared.rescheduleAll(remote)
            return true
        } catch {
            syncState = .failed(error.localizedDescription)
            return false
        }
    }

    func saveAll() async {
        syncState = .syncing
        do {
            let all = try context.fetch(FetchDescriptor<JobApplication>())
            try await api.saveApplications(all.map(JobApplicationDTO.init))
            lastSync = .now
            syncState = .synced
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func add(_ application: JobApplication) {
        context.insert(application)
        try? context.save()
    }

    func delete(_ application: JobApplication) {
        context.delete(application)
        try? context.save()
    }

    func touch(_ application: JobApplication) {
        application.updatedAt = .now
        try? context.save()
        Task { await NotificationManager.shared.scheduleReminder(for: JobApplicationDTO(model: application)) }
    }

    private func upsert(_ remote: [JobApplicationDTO]) throws {
        let local = try context.fetch(FetchDescriptor<JobApplication>())
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIDs = Set(remote.map(\.id))

        for dto in remote {
            let item = byID[dto.id] ?? JobApplication(id: dto.id)
            if byID[dto.id] == nil { context.insert(item) }
            item.company = dto.company
            item.role = dto.role
            item.stage = dto.stage
            item.inviteDate = dto.inviteDate.flatMap { DateFormatters.api.date(from: $0) }
            item.interviewDate = dto.interviewDate.flatMap { DateFormatters.api.date(from: $0) }
            item.statusRaw = dto.status
            item.priorityRaw = dto.priority
            item.nextAction = dto.nextAction
            item.followUpDate = dto.followUpDate.flatMap { DateFormatters.api.date(from: $0) }
            item.contact = dto.contact
            item.mode = dto.mode
            item.notes = dto.notes
            item.updatedAt = .now
        }

        for item in local where !remoteIDs.contains(item.id) { context.delete(item) }
        try context.save()
    }
}

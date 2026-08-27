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
        guard api.isConfigured else { return true }
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
        guard api.isConfigured else { return }
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
        if saveLocal() {
            Task { await NotificationManager.shared.scheduleReminder(for: JobApplicationDTO(model: application)) }
        }
    }

    func delete(_ application: JobApplication) {
        context.delete(application)
        _ = saveLocal()
    }

    /// Apply an AI-detected update: update the matching company or create a new
    /// application. Called only after the user confirms (audit trail).
    @discardableResult
    func applyDetected(_ update: DetectedJobUpdate) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<JobApplication>())) ?? []
        if let existing = bestMatch(for: update, in: all) {
            // Multiple emails can describe the same application. Never let an
            // older confirmation regress an interview back to "Applied".
            if update.status.progressRank >= existing.status.progressRank || update.status.isClosed {
                existing.status = update.status
            }
            if !update.nextAction.isEmpty { existing.nextAction = update.nextAction }
            if existing.role.isEmpty, !update.role.isEmpty { existing.role = update.role }
            if let source = update.sourceMessageID, !existing.relatedEmailThreadIDs.contains(source) {
                existing.relatedEmailThreadIDs.append(source)
            }
            existing.updatedAt = .now
        } else {
            let job = JobApplication(company: update.company, role: update.role,
                                     status: update.status, nextAction: update.nextAction)
            if let source = update.sourceMessageID { job.relatedEmailThreadIDs = [source] }
            context.insert(job)
        }
        return saveLocal()
    }

    func touch(_ application: JobApplication) {
        application.updatedAt = .now
        if saveLocal() {
            Task { await NotificationManager.shared.scheduleReminder(for: JobApplicationDTO(model: application)) }
        }
    }

    /// A read-only local snapshot for assistant context outside a SwiftUI
    /// `@Query` (for example, when Apple Watch requests a voice session).
    func allApplications() -> [JobApplication] {
        let descriptor = FetchDescriptor<JobApplication>(
            sortBy: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func upsert(_ remote: [JobApplicationDTO]) throws {
        let local = try context.fetch(FetchDescriptor<JobApplication>())
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

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

        // The local store also contains manual and Gmail-detected applications
        // that may not have reached the legacy backend yet. A refresh is a merge,
        // never an instruction to delete those local records.
        try context.save()
    }

    private func bestMatch(for update: DetectedJobUpdate, in applications: [JobApplication]) -> JobApplication? {
        if let messageID = update.sourceMessageID,
           let exactSource = applications.first(where: { $0.relatedEmailThreadIDs.contains(messageID) }) {
            return exactSource
        }

        let company = normalized(update.company)
        let role = normalized(update.role)
        let sameCompany = applications.filter { normalized($0.company) == company }
        if role.isEmpty { return sameCompany.count == 1 ? sameCompany[0] : nil }
        return sameCompany.first { normalized($0.role) == role || $0.role.isEmpty }
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @discardableResult
    private func saveLocal() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            syncState = .failed("The local job tracker could not be saved: \(error.localizedDescription)")
            return false
        }
    }
}

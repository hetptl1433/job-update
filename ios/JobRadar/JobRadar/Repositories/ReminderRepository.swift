import Foundation

@MainActor
final class ReminderRepository: ObservableObject {
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var calendarSyncEnabled = false
    @Published private(set) var calendarSyncError: String?
    @Published var openReminderID: UUID?
    @Published var createReminderRequested = false

    private let appleCalendar = AppleCalendarService()

    var open: [ReminderItem] {
        reminders.filter { !$0.isCompleted }.sorted { $0.fireDate < $1.fireDate }
    }
    var completed: [ReminderItem] {
        reminders.filter(\.isCompleted).sorted { $0.updatedAt > $1.updatedAt }
    }

    init() {
        reload()
        calendarSyncEnabled = OrbitIntegrationPreferences.appleCalendarSyncEnabled
    }

    func reload() { reminders = SharedReminderStore.load() }

    func add(_ item: ReminderItem) {
        var value = item
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { return }
        value.updatedAt = .now
        reminders.append(value)
        persistAndSynchronize(value.id)
    }

    func update(_ item: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id }) else { return }
        var value = item
        value.updatedAt = .now
        reminders[index] = value
        persistAndSynchronize(value.id)
    }

    func toggle(_ item: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id }) else { return }
        reminders[index].isCompleted.toggle()
        reminders[index].updatedAt = .now
        persistAndSynchronize(item.id)
    }

    func delete(_ item: ReminderItem) {
        reminders.removeAll { $0.id == item.id }
        Task { await TaskAlertScheduler.shared.cancel(reminderID: item.id) }
        if calendarSyncEnabled {
            do { try appleCalendar.deleteReminderEvent(identifier: item.relatedCalendarEventID) }
            catch { calendarSyncError = error.localizedDescription }
        }
        persist()
    }

    func setAppleCalendarSyncEnabled(_ enabled: Bool) {
        calendarSyncEnabled = enabled
        OrbitIntegrationPreferences.appleCalendarSyncEnabled = enabled
        calendarSyncError = nil
        if enabled {
            reconcileWithAppleCalendar()
        }
    }

    func reconcileWithAppleCalendar() {
        guard calendarSyncEnabled else { return }
        do {
            reminders = try appleCalendar.mergeLinkedReminderChanges(into: reminders)
            persist()
            for reminder in reminders where !reminder.isCompleted {
                synchronizeToApple(reminder.id)
                Task { await TaskAlertScheduler.shared.synchronize(reminder: reminder) }
            }
            calendarSyncError = nil
        } catch {
            calendarSyncError = error.localizedDescription
        }
    }

    private func persistAndSynchronize(_ id: UUID) {
        persist()
        if let reminder = reminders.first(where: { $0.id == id }) {
            Task { await TaskAlertScheduler.shared.synchronize(reminder: reminder) }
        }
        if calendarSyncEnabled { synchronizeToApple(id) }
    }

    private func synchronizeToApple(_ id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        do {
            let identifier = try appleCalendar.synchronize(reminders[index])
            if reminders[index].relatedCalendarEventID != identifier {
                reminders[index].relatedCalendarEventID = identifier
                reminders[index].updatedAt = .now
                persist()
            }
            calendarSyncError = nil
        } catch {
            calendarSyncError = error.localizedDescription
        }
    }

    private func persist() { _ = SharedReminderStore.save(reminders) }
}

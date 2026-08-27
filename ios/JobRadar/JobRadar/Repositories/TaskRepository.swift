import Foundation
import WidgetKit

@MainActor
final class TaskRepository: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var suggestions: [TaskItem] = []
    @Published private(set) var calendarSyncEnabled = false
    @Published private(set) var calendarSyncError: String?
    @Published var openTaskID: UUID?
    @Published var createTaskRequested = false

    private let appleCalendar = AppleCalendarService()
    private let watchSync: WatchTaskSyncService

    var prioritizedOpen: [TaskItem] { SharedTaskStore.prioritized(tasks) }
    var today: [TaskItem] {
        prioritizedOpen.filter { $0.isOverdue || $0.isDueToday || $0.dueDate == nil }
    }
    var completed: [TaskItem] { tasks.filter(\.isCompleted).sorted { $0.updatedAt > $1.updatedAt } }

    init(watchSync: WatchTaskSyncService = .shared) {
        self.watchSync = watchSync
        let migrated = SharedTaskStore.migrateLegacyRemindersIfNeeded()
        watchSync.onTaskCompleted = { [weak self] id in
            self?.completeFromWatch(id)
        }
        watchSync.start()
        reload()
        calendarSyncEnabled = OrbitIntegrationPreferences.appleCalendarSyncEnabled
        for task in migrated {
            // Cancel the legacy notification namespace before scheduling the
            // same item through the unified To Do path.
            Task {
                await TaskAlertScheduler.shared.cancel(reminderID: task.id)
                await TaskAlertScheduler.shared.synchronize(task: task)
            }
            if calendarSyncEnabled { synchronizeToApple(task.id) }
        }
    }

    func reload() {
        tasks = SharedTaskStore.load()
        watchSync.publish(tasks: tasks)
    }

    @discardableResult
    func add(_ item: TaskItem) -> Bool {
        var value = item
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { return false }
        value.updatedAt = .now
        let previous = tasks
        tasks.append(value)
        guard persistAndSynchronize(value.id) else {
            tasks = previous
            return false
        }
        return true
    }

    func update(_ item: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        var value = item
        value.updatedAt = .now
        tasks[index] = value
        persistAndSynchronize(value.id)
    }

    func toggle(_ item: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[index].isCompleted.toggle()
        tasks[index].updatedAt = .now
        persistAndSynchronize(tasks[index].id)
    }

    private func completeFromWatch(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isCompleted else { return }
        tasks[index].isCompleted = true
        tasks[index].updatedAt = .now
        persistAndSynchronize(id)
    }

    func delete(_ item: TaskItem) {
        tasks.removeAll { $0.id == item.id }
        Task { await TaskAlertScheduler.shared.cancel(taskID: item.id) }
        if calendarSyncEnabled {
            do { try appleCalendar.deleteTaskEvent(identifier: item.appleCalendarEventID) }
            catch { calendarSyncError = error.localizedDescription }
        }
        persist()
    }

    func reschedule(_ item: TaskItem, to date: Date?) {
        var value = item
        value.dueDate = date
        update(value)
    }

    func propose(
        from messages: [InboxMessage],
        updates: [DetectedJobUpdate],
        excludingResolvedEmailIDs: Set<String> = []
    ) {
        let existingLinks = Set(tasks.compactMap(\.relatedEmailID))
            .union(excludingResolvedEmailIDs)
        var proposed = messages.filter { $0.actionRequired && !existingLinks.contains($0.id) }.map { message in
            TaskItem(
                title: "Respond: \(message.sender)",
                notes: message.aiSummary,
                dueDate: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now),
                priority: message.importance == .high ? .high : .normal,
                source: .email,
                relatedEmailID: message.id
            )
        }
        proposed += updates.filter { !$0.nextAction.isEmpty && !existingLinks.contains($0.sourceMessageID ?? "") }.map { update in
            TaskItem(
                title: update.nextAction,
                notes: "\(update.company) · \(update.reason)",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                priority: .high,
                source: .ai,
                relatedEmailID: update.sourceMessageID
            )
        }
        suggestions = Dictionary(grouping: proposed, by: { $0.relatedEmailID ?? $0.title.lowercased() })
            .compactMap(\.value.first)
    }

    @discardableResult
    func acceptSuggestion(_ item: TaskItem) -> Bool {
        guard add(item) else { return false }
        suggestions.removeAll { $0.id == item.id }
        return true
    }

    func dismissSuggestion(_ item: TaskItem) { suggestions.removeAll { $0.id == item.id } }

    func setAppleCalendarSyncEnabled(_ enabled: Bool) {
        calendarSyncEnabled = enabled
        OrbitIntegrationPreferences.appleCalendarSyncEnabled = enabled
        calendarSyncError = nil
        if enabled { reconcileWithAppleCalendar() }
    }

    func reconcileWithAppleCalendar() {
        guard calendarSyncEnabled else { return }
        do {
            tasks = try appleCalendar.mergeLinkedTaskChanges(into: tasks)
            persist()
            for task in tasks where !task.isCompleted {
                synchronizeToApple(task.id)
                Task { await TaskAlertScheduler.shared.synchronize(task: task) }
            }
            calendarSyncError = nil
        } catch {
            calendarSyncError = error.localizedDescription
        }
    }

    /// Only tasks the user explicitly created from a calendar event are linked.
    /// Subsequent provider changes update that task; unrelated events are ignored.
    func mergeLinkedCalendarEvents(_ events: [UnifiedCalendarEvent]) {
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changedIDs: [UUID] = []
        for index in tasks.indices {
            guard tasks[index].source == .calendar,
                  let eventID = tasks[index].relatedCalendarEventID,
                  let event = byID[eventID] else { continue }
            if tasks[index].title != event.title || tasks[index].dueDate != event.start {
                tasks[index].title = event.title
                tasks[index].dueDate = event.start
                tasks[index].updatedAt = .now
                changedIDs.append(tasks[index].id)
            }
        }
        if !changedIDs.isEmpty {
            persist()
            for id in changedIDs {
                guard let task = tasks.first(where: { $0.id == id }) else { continue }
                Task { await TaskAlertScheduler.shared.synchronize(task: task) }
            }
        }
    }

    @discardableResult
    private func persistAndSynchronize(_ id: UUID) -> Bool {
        guard persist() else { return false }
        guard let task = tasks.first(where: { $0.id == id }) else { return true }
        Task { await TaskAlertScheduler.shared.synchronize(task: task) }
        if calendarSyncEnabled { synchronizeToApple(id) }
        return true
    }

    private func synchronizeToApple(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        do {
            let identifier = try appleCalendar.synchronize(tasks[index])
            if tasks[index].appleCalendarEventID != identifier {
                tasks[index].appleCalendarEventID = identifier
                tasks[index].updatedAt = .now
                persist()
            }
            calendarSyncError = nil
        } catch {
            calendarSyncError = error.localizedDescription
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard SharedTaskStore.save(tasks) else { return false }
        watchSync.publish(tasks: tasks)
        WidgetCenter.shared.reloadTimelines(ofKind: "OrbitTasksWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "OrbitRemindersWidget")
        return true
    }
}

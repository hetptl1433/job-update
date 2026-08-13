import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, normal, high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TaskSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, email, job, calendar, ai, automation

    var id: String { rawValue }
    var label: String { self == .ai ? "AI" : rawValue.capitalized }
}

enum TaskAlertStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case alarm, notification, none

    var id: String { rawValue }
    var label: String {
        switch self {
        case .alarm: "Alarm"
        case .notification: "Notification"
        case .none: "No alert"
        }
    }
}

/// Orbit's single To Do model. Items without a date stay local; adding a date
/// and time makes the same item eligible for alerts and Apple Calendar sync.
struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var source: TaskSource
    var relatedEmailID: String?
    var relatedJobApplicationID: Int?
    var relatedCalendarEventID: String?
    /// The Apple Calendar event created for this task. This is intentionally
    /// separate from `relatedCalendarEventID`, which tracks an event that the
    /// user manually converted into a To Do.
    var appleCalendarEventID: String?
    /// Optional for backward-compatible decoding. A timed item with no stored
    /// choice uses `.alarm`, which is the product default.
    var alertStyle: TaskAlertStyle?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .normal,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        source: TaskSource = .manual,
        relatedEmailID: String? = nil,
        relatedJobApplicationID: Int? = nil,
        relatedCalendarEventID: String? = nil,
        appleCalendarEventID: String? = nil,
        alertStyle: TaskAlertStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.relatedEmailID = relatedEmailID
        self.relatedJobApplicationID = relatedJobApplicationID
        self.relatedCalendarEventID = relatedCalendarEventID
        self.appleCalendarEventID = appleCalendarEventID
        self.alertStyle = alertStyle
    }

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var effectiveAlertStyle: TaskAlertStyle { alertStyle ?? .alarm }
}

/// Legacy storage model retained only so existing Reminder data can be migrated
/// into `TaskItem` after the unified To Do experience ships.
struct ReminderItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var fireDate: Date
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var relatedTaskID: UUID?
    var relatedCalendarEventID: String?
    var alertStyle: TaskAlertStyle?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        fireDate: Date = .now,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relatedTaskID: UUID? = nil,
        relatedCalendarEventID: String? = nil,
        alertStyle: TaskAlertStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.fireDate = fireDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relatedTaskID = relatedTaskID
        self.relatedCalendarEventID = relatedCalendarEventID
        self.alertStyle = alertStyle
    }


    var effectiveAlertStyle: TaskAlertStyle { alertStyle ?? .alarm }
}

enum SharedTaskStore {
    static let appGroupID = "group.com.hetpatel.jobradar"
    static let storageKey = "orbit.tasks.v1"
    private static let reminderMigrationKey = "orbit.tasks.reminderMigration.v1"

    static func load() -> [TaskItem] {
        guard let data = defaults.data(forKey: storageKey),
              let tasks = try? JSONDecoder().decode([TaskItem].self, from: data) else { return [] }
        return tasks
    }

    @discardableResult
    static func save(_ tasks: [TaskItem]) -> Bool {
        guard let data = try? JSONEncoder().encode(tasks) else { return false }
        defaults.set(data, forKey: storageKey)
        return defaults.synchronize()
    }

    @discardableResult
    static func complete(id: UUID) -> Bool {
        var tasks = load()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        tasks[index].isCompleted.toggle()
        tasks[index].updatedAt = .now
        return save(tasks)
    }

    static func prioritized(_ tasks: [TaskItem], includingCompleted: Bool = false) -> [TaskItem] {
        tasks
            .filter { includingCompleted || !$0.isCompleted }
            .sorted { lhs, rhs in
                let a = rank(lhs)
                let b = rank(rhs)
                if a != b { return a < b }
                if lhs.dueDate != rhs.dueDate {
                    return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// One-time, lossless migration from the former separate Reminder list.
    /// IDs and linked Apple Calendar identifiers are retained so old deep links,
    /// alerts, and calendar events continue to resolve to the unified To Do.
    @discardableResult
    static func migrateLegacyRemindersIfNeeded() -> [TaskItem] {
        guard !defaults.bool(forKey: reminderMigrationKey) else { return [] }
        let reminders = SharedReminderStore.load()
        let existing = load()
        let merged = merging(existing, with: reminders)
        let migratedIDs = Set(merged.map(\.id)).subtracting(Set(existing.map(\.id)))
        let migrated = merged.filter { migratedIDs.contains($0.id) }

        guard save(merged) else { return [] }
        _ = SharedReminderStore.save([])
        defaults.set(true, forKey: reminderMigrationKey)
        return migrated
    }

    /// Pure merge used by the migration and unit tests. Existing To Dos win an
    /// unlikely UUID collision so migration can never overwrite current data.
    static func merging(_ tasks: [TaskItem], with reminders: [ReminderItem]) -> [TaskItem] {
        var result = tasks
        var existingIDs = Set(tasks.map(\.id))
        for reminder in reminders where !existingIDs.contains(reminder.id) {
            result.append(TaskItem(
                id: reminder.id,
                title: reminder.title,
                notes: reminder.notes,
                dueDate: reminder.fireDate,
                priority: .normal,
                isCompleted: reminder.isCompleted,
                createdAt: reminder.createdAt,
                updatedAt: reminder.updatedAt,
                source: .manual,
                appleCalendarEventID: reminder.relatedCalendarEventID,
                alertStyle: reminder.alertStyle
            ))
            existingIDs.insert(reminder.id)
        }
        return result
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static func rank(_ task: TaskItem) -> Int {
        if task.isOverdue { return 0 }
        if task.isDueToday { return 1 }
        if task.priority == .high { return 2 }
        if task.source == .ai || task.source == .email { return 3 }
        return 4
    }
}

enum SharedReminderStore {
    static let storageKey = "orbit.reminders.v1"

    static func load() -> [ReminderItem] {
        guard let data = defaults.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([ReminderItem].self, from: data) else { return [] }
        return values
    }

    @discardableResult
    static func save(_ reminders: [ReminderItem]) -> Bool {
        guard let data = try? JSONEncoder().encode(reminders) else { return false }
        defaults.set(data, forKey: storageKey)
        return defaults.synchronize()
    }

    @discardableResult
    static func complete(id: UUID) -> Bool {
        var reminders = load()
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return false }
        reminders[index].isCompleted.toggle()
        reminders[index].updatedAt = .now
        return save(reminders)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedTaskStore.appGroupID) ?? .standard
    }
}

enum OrbitIntegrationPreferences {
    static let appleCalendarSyncKey = "orbit.appleCalendarSyncEnabled"

    static var appleCalendarSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: appleCalendarSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: appleCalendarSyncKey) }
    }
}

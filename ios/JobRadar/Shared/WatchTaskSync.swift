import Foundation

/// A Foundation-only task representation shared by the iPhone and Watch
/// targets. The Watch deliberately receives a snapshot instead of depending on
/// the iPhone app's local app-group store, which does not span devices.
struct WatchTaskSnapshotItem: Codable, Identifiable, Hashable, Sendable {
    enum Priority: String, Codable, Hashable, Sendable {
        case low, normal, high
    }

    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: Priority
    var updatedAt: Date

    func isOverdue(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return dueDate < calendar.startOfDay(for: date)
    }

    func isDueToday(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: date)
    }
}

struct WatchTaskSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var generatedAt: Date
    var tasks: [WatchTaskSnapshotItem]
}

enum WatchTaskSyncProtocol {
    static let snapshotKey = "orbit.watch.tasks.snapshot.v1"
    static let completedTaskIDKey = "orbit.watch.tasks.completed-id"
    static let completedValueKey = "orbit.watch.tasks.completed-value"
    static let requestSnapshotKey = "orbit.watch.tasks.request-snapshot"
    static let acknowledgementKey = "orbit.watch.tasks.acknowledged"

    static func context(for snapshot: WatchTaskSnapshot) throws -> [String: Any] {
        [snapshotKey: try JSONEncoder().encode(snapshot)]
    }

    static func snapshot(from context: [String: Any]) -> WatchTaskSnapshot? {
        guard let data = context[snapshotKey] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchTaskSnapshot.self, from: data),
              snapshot.version == WatchTaskSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }

    static func completionMessage(taskID: UUID) -> [String: Any] {
        [
            completedTaskIDKey: taskID.uuidString,
            completedValueKey: true
        ]
    }

    static func completedTaskID(from message: [String: Any]) -> UUID? {
        guard message[completedValueKey] as? Bool == true,
              let value = message[completedTaskIDKey] as? String else {
            return nil
        }
        return UUID(uuidString: value)
    }
}

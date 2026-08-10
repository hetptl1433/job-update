import AppIntents
import AlarmKit
import EventKit
import Foundation
import UserNotifications
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Orbit Task"
    static var description = IntentDescription("Marks an Orbit task complete or incomplete.")
    static var openAppWhenRun = false

    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let task = SharedTaskStore.load().first { $0.id == id }
        _ = SharedTaskStore.complete(id: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["orbit-task-\(id.uuidString)"]
        )
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: id) }
        SharedCalendarEventDeletion.remove(identifier: task?.appleCalendarEventID)
        WidgetCenter.shared.reloadTimelines(ofKind: "OrbitTasksWidget")
        return .result()
    }
}

enum SharedCalendarEventDeletion {
    static func remove(identifier: String?) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let identifier else { return }
        let raw = identifier.hasPrefix("apple:")
            ? String(identifier.dropFirst("apple:".count)) : identifier
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: raw) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }
}

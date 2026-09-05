import AppIntents
import AlarmKit
import Foundation
import UserNotifications
import WidgetKit

struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Orbit Reminder"
    static var description = IntentDescription("Marks an Orbit reminder complete.")
    static var openAppWhenRun = false

    @Parameter(title: "Reminder ID") var reminderID: String

    init() {}
    init(reminderID: String) { self.reminderID = reminderID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        if let task = SharedTaskStore.load().first(where: { $0.id == id }) {
            guard SharedTaskStore.setCompletion(id: id, isCompleted: true) else { return .result() }
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["orbit-task-\(id.uuidString)", "orbit-reminder-\(id.uuidString)"]
            )
            if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: id) }
            SharedCalendarEventDeletion.remove(identifier: task.appleCalendarEventID)
            WidgetCenter.shared.reloadTimelines(ofKind: "OrbitTasksWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "OrbitRemindersWidget")
            return .result()
        }

        // Fallback for an old widget timeline invoked before the app has had a
        // chance to run the one-time Reminder-to-To-Do migration.
        guard let reminder = SharedReminderStore.load().first(where: { $0.id == id }),
              SharedReminderStore.setCompletion(id: id, isCompleted: true) else { return .result() }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["orbit-reminder-\(id.uuidString)"]
        )
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: id) }
        SharedCalendarEventDeletion.remove(identifier: reminder.relatedCalendarEventID)
        WidgetCenter.shared.reloadTimelines(ofKind: "OrbitRemindersWidget")
        return .result()
    }
}

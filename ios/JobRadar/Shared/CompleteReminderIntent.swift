import AppIntents
import AlarmKit
import Foundation
import UserNotifications
import WidgetKit

struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Orbit Reminder"
    static var description = IntentDescription("Marks an Orbit reminder complete or incomplete.")
    static var openAppWhenRun = false

    @Parameter(title: "Reminder ID") var reminderID: String

    init() {}
    init(reminderID: String) { self.reminderID = reminderID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        let reminder = SharedReminderStore.load().first { $0.id == id }
        _ = SharedReminderStore.complete(id: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["orbit-reminder-\(id.uuidString)"]
        )
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: id) }
        SharedCalendarEventDeletion.remove(identifier: reminder?.relatedCalendarEventID)
        WidgetCenter.shared.reloadTimelines(ofKind: "OrbitRemindersWidget")
        return .result()
    }
}

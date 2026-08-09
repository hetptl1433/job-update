import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Local notification scheduling. Note: reliable server-side monitoring (new
/// email, recruiter replies) is a backend + APNs concern; on-device scheduling
/// only covers deterministic local reminders (follow-ups, digests).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    func scheduleReminder(for application: JobApplicationDTO) async {
        let identifier = "job-reminder-\(application.id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let dateText = application.followUpDate,
              let date = DateFormatters.api.date(from: dateText),
              !JobStatus(normalizing: application.status).isClosed else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        let content = UNMutableNotificationContent()
        content.title = "Follow up with \(application.company)"
        content.body = application.nextAction.isEmpty ? "Check the latest status for \(application.role)." : application.nextAction
        content.sound = .default
        content.userInfo = ["applicationID": application.id]
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    func scheduleDailyDigest(hour: Int = 6) async {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-brief"])
        let content = UNMutableNotificationContent()
        content.title = AppConfig.appName
        content.body = "Your morning brief is ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "daily-brief", content: content, trigger: trigger))
    }

    func cancelDailyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-brief"])
    }

    func rescheduleAll(_ applications: [JobApplicationDTO]) async {
        for application in applications { await scheduleReminder(for: application) }
    }
}

/// Registers and schedules background refresh. Real monitoring should live on
/// the backend; this only opportunistically refreshes cached data.
@MainActor
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    static let identifier = "com.hetpatel.jobradar.refresh"
    var refreshHandler: (() async -> Bool)?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.schedule()
                let success = await self.refreshHandler?() ?? false
                refreshTask.setTaskCompleted(success: success)
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

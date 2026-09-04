import AlarmKit
import Foundation
import SwiftUI

/// One delivery path for timed To Dos and Reminders. AlarmKit supplies a real
/// prominent alarm on iOS 26+. Earlier systems fall back to a sound notification.
@MainActor
final class TaskAlertScheduler {
    static let shared = TaskAlertScheduler()

    /// AlarmKit renders its templated alert on a dark system surface. Keep this
    /// color fixed and high-contrast instead of inheriting an adaptive app tint;
    /// black makes the alarm title and controls appear blank on that surface.
    private static let presentationTint = Color(
        red: 243.0 / 255.0,
        green: 38.0 / 255.0,
        blue: 62.0 / 255.0
    )
    private static let presentationVersion = 1
    private static let presentationVersionKey = "orbit.taskAlerts.presentationVersion"
    private let preferences = UserDefaults(suiteName: SharedTaskStore.appGroupID) ?? .standard

    /// AlarmKit snapshots presentation attributes when an alarm is scheduled.
    /// Refresh pending alarms once after a presentation change so existing To
    /// Dos don't retain stale colors from an earlier app version.
    func refreshPendingAlarmPresentationsIfNeeded(tasks: [TaskItem]) async {
        guard #available(iOS 26.0, *),
              preferences.integer(forKey: Self.presentationVersionKey) < Self.presentationVersion else {
            return
        }

        for task in tasks where !task.isCompleted
            && task.effectiveAlertStyle == .alarm
            && task.dueDate.map({ $0 > .now }) == true {
            await synchronize(task: task)
        }

        preferences.set(Self.presentationVersion, forKey: Self.presentationVersionKey)
    }

    func synchronize(task: TaskItem) async {
        await cancel(taskID: task.id)
        guard !task.isCompleted, let date = task.dueDate, date > .now else { return }
        await schedule(
            id: task.id,
            title: task.title,
            body: task.notes.isEmpty ? "Orbit To Do" : task.notes,
            date: date,
            style: task.effectiveAlertStyle,
            isReminder: false
        )
    }

    func synchronize(reminder: ReminderItem) async {
        await cancel(reminderID: reminder.id)
        guard !reminder.isCompleted, reminder.fireDate > .now else { return }
        await schedule(
            id: reminder.id,
            title: reminder.title,
            body: reminder.notes.isEmpty ? "Orbit reminder" : reminder.notes,
            date: reminder.fireDate,
            style: reminder.effectiveAlertStyle,
            isReminder: true
        )
    }

    func cancel(taskID: UUID) async {
        NotificationManager.shared.cancelTaskAlert(id: taskID)
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: taskID) }
    }

    func cancel(reminderID: UUID) async {
        NotificationManager.shared.cancelReminder(id: reminderID)
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: reminderID) }
    }

    private func schedule(
        id: UUID,
        title: String,
        body: String,
        date: Date,
        style: TaskAlertStyle,
        isReminder: Bool
    ) async {
        switch style {
        case .alarm:
            if #available(iOS 26.0, *), await scheduleAlarm(id: id, title: title, date: date) {
                return
            }
            if isReminder {
                await NotificationManager.shared.scheduleReminderNotification(
                    id: id, title: title, body: body, date: date
                )
            } else {
                await NotificationManager.shared.scheduleTaskNotification(
                    id: id, title: title, body: body, date: date
                )
            }
        case .notification:
            if isReminder {
                await NotificationManager.shared.scheduleReminderNotification(
                    id: id, title: title, body: body, date: date
                )
            } else {
                await NotificationManager.shared.scheduleTaskNotification(
                    id: id, title: title, body: body, date: date
                )
            }
        case .none:
            break
        }
    }

    @available(iOS 26.0, *)
    private func scheduleAlarm(id: UUID, title: String, date: Date) async -> Bool {
        do {
            let manager = AlarmManager.shared
            let authorization: AlarmManager.AuthorizationState
            if manager.authorizationState == .notDetermined {
                authorization = try await manager.requestAuthorization()
            } else {
                authorization = manager.authorizationState
            }
            guard authorization == .authorized else { return false }

            let resource = LocalizedStringResource(String.LocalizationValue(title))
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: resource)
            } else {
                alert = AlarmPresentation.Alert(
                    title: resource,
                    stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
                )
            }
            let presentation = AlarmPresentation(alert: alert)
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: OrbitAlarmMetadata(itemID: id),
                tintColor: Self.presentationTint
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(date), attributes: attributes
            )
            _ = try await manager.schedule(id: id, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}

@available(iOS 26.0, *)
private struct OrbitAlarmMetadata: AlarmMetadata {
    let itemID: UUID
}

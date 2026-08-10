import AlarmKit
import Foundation
import SwiftUI

/// One delivery path for timed To Dos and Reminders. AlarmKit supplies a real
/// prominent alarm on iOS 26+. Earlier systems fall back to a sound notification.
@MainActor
final class TaskAlertScheduler {
    static let shared = TaskAlertScheduler()

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
                tintColor: .black
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

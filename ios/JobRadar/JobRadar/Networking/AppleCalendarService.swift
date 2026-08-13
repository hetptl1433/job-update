import EventKit
import Foundation

enum AppleCalendarError: LocalizedError {
    case unavailable
    case permissionDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Calendar is not available on this device."
        case .permissionDenied: "Calendar access was not approved. You can change it in iPhone Settings."
        case .noWritableCalendar: "Apple Calendar has no writable default calendar. Create one in Calendar, then try again."
        }
    }
}

/// EventKit adapter. Provider events are normalized for reading. Orbit only
/// changes events it created for a timed To Do, identified by a
/// stored EventKit identifier and an Orbit marker in the event notes.
@MainActor
final class AppleCalendarService: CalendarProviderService {
    let provider: CalendarProviderType = .apple
    private let store = EKEventStore()

    func requestAccess() async throws {
        guard EKEventStore.authorizationStatus(for: .event) != .restricted else {
            throw AppleCalendarError.unavailable
        }
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw AppleCalendarError.permissionDenied }
    }

    func upcomingEvents(token: String? = nil) async throws -> [UnifiedCalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw AppleCalendarError.permissionDenied
        }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            let title = event.title?.isEmpty == false ? event.title! : "Untitled event"
            let lower = title.lowercased()
            let jobRelated = ["interview", "recruiter", "assessment", "hiring", "candidate", "follow-up", "deadline"]
                .contains { lower.contains($0) }
            return UnifiedCalendarEvent(
                id: "apple:\(event.eventIdentifier ?? UUID().uuidString)",
                provider: .apple,
                calendarID: event.calendar.calendarIdentifier,
                title: title,
                start: event.startDate,
                end: event.endDate,
                location: event.location,
                notes: event.notes,
                meetingURL: event.url,
                isAllDay: event.isAllDay,
                relatedJobApplicationID: nil,
                isImportant: jobRelated
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Legacy Reminder adapter retained while existing data migrates to To Do.
    func synchronize(_ reminder: ReminderItem) throws -> String? {
        try requireFullAccess()
        if reminder.isCompleted {
            try deleteReminderEvent(identifier: reminder.relatedCalendarEventID)
            return nil
        }

        let event: EKEvent
        if let identifier = reminder.relatedCalendarEventID,
           let existing = store.event(withIdentifier: rawIdentifier(identifier)) {
            event = existing
        } else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw AppleCalendarError.noWritableCalendar
            }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }

        event.title = reminder.title
        event.startDate = reminder.fireDate
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: reminder.fireDate)
            ?? reminder.fireDate.addingTimeInterval(1_800)
        event.isAllDay = false
        event.notes = reminderNotes(reminder)
        event.url = URL(string: "orbit://reminders/\(reminder.id.uuidString)")
        // Orbit owns alarm/notification delivery so Calendar doesn't duplicate it.
        event.alarms = []
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Mirrors a newly-created timed To Do into Apple Calendar. Tasks that were
    /// manually created from an existing provider event already have a calendar
    /// source and are not duplicated into a second Apple event.
    func synchronize(_ task: TaskItem) throws -> String? {
        try requireFullAccess()
        guard task.source != .calendar else { return task.appleCalendarEventID }
        guard !task.isCompleted, let dueDate = task.dueDate else {
            try deleteTaskEvent(identifier: task.appleCalendarEventID)
            return nil
        }

        let event: EKEvent
        if let identifier = task.appleCalendarEventID,
           let existing = store.event(withIdentifier: rawIdentifier(identifier)) {
            event = existing
        } else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw AppleCalendarError.noWritableCalendar
            }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }

        event.title = task.title
        event.startDate = dueDate
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: dueDate)
            ?? dueDate.addingTimeInterval(1_800)
        event.isAllDay = false
        event.notes = taskNotes(task)
        event.url = URL(string: "orbit://tasks/\(task.id.uuidString)")
        event.alarms = []
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func deleteReminderEvent(identifier: String?) throws {
        try requireFullAccess()
        guard let identifier,
              let event = store.event(withIdentifier: rawIdentifier(identifier)) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func deleteTaskEvent(identifier: String?) throws {
        try requireFullAccess()
        guard let identifier,
              let event = store.event(withIdentifier: rawIdentifier(identifier)) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// Pulls edits made in Apple Calendar back into already-linked reminders.
    /// Deleting a linked event completes the reminder rather than deleting data.
    func mergeLinkedReminderChanges(into input: [ReminderItem]) throws -> [ReminderItem] {
        try requireFullAccess()
        return input.map { original in
            guard let identifier = original.relatedCalendarEventID else { return original }
            var reminder = original
            guard let event = store.event(withIdentifier: rawIdentifier(identifier)) else {
                reminder.isCompleted = true
                reminder.relatedCalendarEventID = nil
                reminder.updatedAt = .now
                return reminder
            }

            let calendarNotes = cleanedReminderNotes(event.notes ?? "")
            let changed = reminder.title != event.title
                || reminder.notes != calendarNotes
                || reminder.fireDate != event.startDate
            guard changed else { return reminder }
            reminder.title = event.title?.isEmpty == false ? event.title! : reminder.title
            reminder.notes = calendarNotes
            reminder.fireDate = event.startDate
            reminder.updatedAt = .now
            return reminder
        }
    }

    /// Pulls edits to Orbit-created task events back into To Do. Deleting the
    /// calendar event removes the schedule but preserves the To Do itself.
    func mergeLinkedTaskChanges(into input: [TaskItem]) throws -> [TaskItem] {
        try requireFullAccess()
        return input.map { original in
            guard let identifier = original.appleCalendarEventID else { return original }
            var task = original
            guard let event = store.event(withIdentifier: rawIdentifier(identifier)) else {
                task.dueDate = nil
                task.appleCalendarEventID = nil
                task.updatedAt = .now
                return task
            }

            let calendarNotes = cleanedTaskNotes(event.notes ?? "")
            let changed = task.title != event.title
                || task.notes != calendarNotes
                || task.dueDate != event.startDate
            guard changed else { return task }
            task.title = event.title?.isEmpty == false ? event.title! : task.title
            task.notes = calendarNotes
            task.dueDate = event.startDate
            task.updatedAt = .now
            return task
        }
    }

    private func requireFullAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw AppleCalendarError.permissionDenied
        }
    }

    private func rawIdentifier(_ value: String) -> String {
        value.hasPrefix("apple:") ? String(value.dropFirst("apple:".count)) : value
    }

    private func reminderNotes(_ reminder: ReminderItem) -> String {
        let marker = "Orbit reminder ID: \(reminder.id.uuidString)"
        return reminder.notes.isEmpty ? marker : "\(reminder.notes)\n\n\(marker)"
    }

    private func taskNotes(_ task: TaskItem) -> String {
        let marker = "Orbit task ID: \(task.id.uuidString)"
        return task.notes.isEmpty ? marker : "\(task.notes)\n\n\(marker)"
    }

    private func cleanedReminderNotes(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\n*Orbit reminder ID: [0-9A-Fa-f-]+\s*$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedTaskNotes(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\n*Orbit task ID: [0-9A-Fa-f-]+\s*$"#,
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n*Orbit reminder ID: [0-9A-Fa-f-]+\s*$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

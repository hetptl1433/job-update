import AppIntents
import Foundation
import WidgetKit

enum OrbitIntentAlertStyle: String, AppEnum {
    case alarm, notification, none

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Alert")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .alarm: "Alarm",
        .notification: "Notification",
        .none: "No alert"
    ]

    var taskStyle: TaskAlertStyle { TaskAlertStyle(rawValue: rawValue) ?? .alarm }
}

struct CreateOrbitTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Orbit To Do"
    static var description = IntentDescription("Creates a To Do in Orbit, optionally with a time and alert.")
    static var openAppWhenRun = false

    @Parameter(
        title: "To Do",
        requestValueDialog: "What should Orbit add? You can include a time."
    ) var task: String
    @Parameter(title: "When") var dueDate: Date?
    @Parameter(title: "Alert") var alert: OrbitIntentAlertStyle

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$task) due \(\.$dueDate) with \(\.$alert)")
    }

    init() { alert = .alarm }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let spokenInput = OrbitSpokenInput(task)
        let resolvedDate = dueDate ?? spokenInput.date
        _ = await OrbitIntentWriter.createTask(
            title: spokenInput.title,
            dueDate: resolvedDate,
            alertStyle: alert.taskStyle
        )
        return .result(dialog: "Added to Orbit To Do.")
    }
}

struct CreateOrbitReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Orbit Reminder"
    static var description = IntentDescription("Creates a timed reminder in Orbit.")
    static var openAppWhenRun = false

    @Parameter(
        title: "Reminder",
        requestValueDialog: "What should Orbit remind you about? You can include a time."
    ) var reminder: String
    @Parameter(title: "When") var fireDate: Date?
    @Parameter(title: "Alert") var alert: OrbitIntentAlertStyle

    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to \(\.$reminder) at \(\.$fireDate) with \(\.$alert)")
    }

    init() { alert = .alarm }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let spokenInput = OrbitSpokenInput(reminder)
        guard let resolvedDate = fireDate ?? spokenInput.date else {
            throw $fireDate.needsValueError("When should Orbit remind you?")
        }
        _ = await OrbitIntentWriter.createReminder(
            title: spokenInput.title,
            fireDate: resolvedDate,
            alertStyle: alert.taskStyle
        )
        return .result(dialog: "Reminder added to Orbit.")
    }
}

struct OrbitAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateOrbitTaskIntent(),
            phrases: [
                "Create a To Do in \(.applicationName)",
                "Add a To Do to \(.applicationName)",
                "Add a task to \(.applicationName)",
                "Make a task in \(.applicationName)",
                "Set a task in \(.applicationName)",
                "Set this task on \(.applicationName)"
            ],
            shortTitle: "Add To Do",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: CreateOrbitReminderIntent(),
            phrases: [
                "Create a reminder in \(.applicationName)",
                "Remind me with \(.applicationName)",
                "Make a reminder in \(.applicationName)",
                "Set a reminder in \(.applicationName)",
                "Set this reminder on \(.applicationName)"
            ],
            shortTitle: "Add Reminder",
            systemImageName: "alarm"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .grayBlue }
}

private struct OrbitSpokenInput {
    let title: String
    let date: Date?

    init(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ), let match = detector.firstMatch(
            in: value,
            options: [],
            range: NSRange(value.startIndex..., in: value)
        ), let detectedDate = match.date else {
            title = Self.cleanedTitle(value)
            date = nil
            return
        }

        if detectedDate <= .now, Calendar.current.isDateInToday(detectedDate) {
            date = Calendar.current.date(byAdding: .day, value: 1, to: detectedDate)
        } else {
            date = detectedDate
        }
        let valueWithoutDate = (value as NSString).replacingCharacters(in: match.range, with: "")
        title = Self.cleanedTitle(valueWithoutDate)
    }

    private static func cleanedTitle(_ input: String) -> String {
        var result = input.replacingOccurrences(
            of: #"\s*(and\s+)?(put|set|use)\s+(an?\s+)?alarm(\s+for\s+it)?\s*"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s+\b(for|at|on)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }
}

@MainActor
private enum OrbitIntentWriter {
    static func createTask(
        title: String,
        dueDate: Date?,
        alertStyle: TaskAlertStyle
    ) async -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        var item = TaskItem(
            title: cleanTitle,
            dueDate: dueDate,
            alertStyle: dueDate == nil ? .none : alertStyle
        )
        var values = SharedTaskStore.load()
        values.append(item)
        _ = SharedTaskStore.save(values)
        await TaskAlertScheduler.shared.synchronize(task: item)

        if dueDate != nil, OrbitIntegrationPreferences.appleCalendarSyncEnabled,
           let identifier = try? AppleCalendarService().synchronize(item) {
            item.appleCalendarEventID = identifier
            if let index = values.firstIndex(where: { $0.id == item.id }) {
                values[index] = item
                _ = SharedTaskStore.save(values)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return item
    }

    static func createReminder(
        title: String,
        fireDate: Date,
        alertStyle: TaskAlertStyle
    ) async -> ReminderItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        var item = ReminderItem(
            title: cleanTitle,
            fireDate: fireDate,
            alertStyle: alertStyle
        )
        var values = SharedReminderStore.load()
        values.append(item)
        _ = SharedReminderStore.save(values)
        await TaskAlertScheduler.shared.synchronize(reminder: item)

        if OrbitIntegrationPreferences.appleCalendarSyncEnabled,
           let identifier = try? AppleCalendarService().synchronize(item) {
            item.relatedCalendarEventID = identifier
            if let index = values.firstIndex(where: { $0.id == item.id }) {
                values[index] = item
                _ = SharedReminderStore.save(values)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return item
    }
}

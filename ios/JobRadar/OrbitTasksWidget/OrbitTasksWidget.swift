import SwiftUI
import WidgetKit

private struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
}

private struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { TasksEntry(date: .now, tasks: []) }
    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(TasksEntry(date: .now, tasks: SharedTaskStore.prioritized(SharedTaskStore.load())))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let entry = TasksEntry(date: .now, tasks: SharedTaskStore.prioritized(SharedTaskStore.load()))
        let refresh = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now.addingTimeInterval(1_200)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TasksEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Link(destination: URL(string: "orbit://tasks")!) {
                    Text("TODAY").font(.caption.weight(.bold)).tracking(0.8)
                }
                .foregroundStyle(.primary)
                Spacer()
                Text("\(entry.tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Link(destination: URL(string: "orbit://tasks/new")!) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .padding(.bottom, 8)

            if entry.tasks.isEmpty {
                Spacer()
                Label("All clear", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Link(destination: URL(string: "orbit://tasks/\(task.id.uuidString)")!) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).font(.caption.weight(.medium)).lineLimit(1)
                                if family != .systemSmall, let detail = detail(task) {
                                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, family == .systemLarge ? 5 : 3)
                    if task.id != entry.tasks.prefix(limit).last?.id { Divider().opacity(0.45) }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func detail(_ task: TaskItem) -> String? {
        if task.isOverdue { return "Overdue" }
        if let date = task.dueDate {
            return date.formatted(date: task.isDueToday ? .omitted : .abbreviated, time: .shortened)
        }
        return task.source == .manual ? nil : task.source.label
    }
}

struct OrbitTasksWidget: Widget {
    let kind = "OrbitTasksWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Orbit Today")
        .description("Your highest-priority Orbit tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct RemindersEntry: TimelineEntry {
    let date: Date
    let reminders: [ReminderItem]
}

private struct RemindersProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindersEntry { RemindersEntry(date: .now, reminders: []) }
    func getSnapshot(in context: Context, completion: @escaping (RemindersEntry) -> Void) {
        completion(RemindersEntry(date: .now, reminders: openReminders()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindersEntry>) -> Void) {
        let entry = RemindersEntry(date: .now, reminders: openReminders())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func openReminders() -> [ReminderItem] {
        SharedReminderStore.load().filter { !$0.isCompleted }.sorted { $0.fireDate < $1.fireDate }
    }
}

private struct RemindersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemindersEntry

    private var limit: Int { family == .systemSmall ? 3 : (family == .systemLarge ? 9 : 5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Link(destination: URL(string: "orbit://reminders")!) {
                    Text("REMINDERS").font(.caption.weight(.bold)).tracking(0.8)
                }
                .foregroundStyle(.primary)
                Spacer()
                Text("\(entry.reminders.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Link(destination: URL(string: "orbit://reminders/new")!) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .padding(.bottom, 8)

            if entry.reminders.isEmpty {
                Spacer()
                Label("No reminders", systemImage: "bell.slash")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.reminders.prefix(limit)) { reminder in
                    HStack(spacing: 7) {
                        Button(intent: CompleteReminderIntent(reminderID: reminder.id.uuidString)) {
                            Image(systemName: "circle").font(.caption)
                        }
                        .buttonStyle(.plain)
                        Link(destination: URL(string: "orbit://reminders/\(reminder.id.uuidString)")!) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reminder.title).font(.caption.weight(.medium)).lineLimit(1)
                                if family != .systemSmall {
                                    Text(reminder.fireDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, family == .systemLarge ? 5 : 3)
                    if reminder.id != entry.reminders.prefix(limit).last?.id { Divider().opacity(0.45) }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct OrbitRemindersWidget: Widget {
    let kind = "OrbitRemindersWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RemindersProvider()) { entry in
            RemindersWidgetView(entry: entry)
        }
        .configurationDisplayName("Orbit Reminders")
        .description("Upcoming Orbit reminders with quick add and complete actions.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct VoiceEntry: TimelineEntry {
    let date: Date
}

private struct VoiceProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoiceEntry { VoiceEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (VoiceEntry) -> Void) {
        completion(VoiceEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoiceEntry>) -> Void) {
        completion(Timeline(entries: [VoiceEntry(date: .now)], policy: .never))
    }
}

private struct VoiceWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.title3.weight(.semibold))
                .widgetAccentable()
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "orbit://voice")!)
        .accessibilityLabel("Talk to Orbit")
    }
}

struct OrbitVoiceWidget: Widget {
    let kind = "OrbitVoiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoiceProvider()) { _ in
            VoiceWidgetView()
        }
        .configurationDisplayName("Talk to Orbit")
        .description("Open Orbit voice mode.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct OrbitTasksWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbitTasksWidget()
        OrbitRemindersWidget()
        OrbitVoiceWidget()
    }
}

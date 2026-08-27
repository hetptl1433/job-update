import AppIntents
import SwiftUI
import WidgetKit

private struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
}

private struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, tasks: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let refresh = Calendar.current.date(byAdding: .minute, value: 20, to: .now)
            ?? .now.addingTimeInterval(1_200)
        completion(Timeline(entries: [entry()], policy: .after(refresh)))
    }

    private func entry() -> TasksEntry {
        TasksEntry(
            date: .now,
            tasks: SharedTaskStore.prioritized(SharedTaskStore.load())
        )
    }
}

private struct ScheduledTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, tasks: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry()], policy: .after(refresh)))
    }

    private func entry() -> TasksEntry {
        let scheduled = SharedTaskStore.prioritized(SharedTaskStore.load())
            .filter { $0.dueDate != nil }
        return TasksEntry(date: .now, tasks: scheduled)
    }
}

private struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TasksEntry
    var scheduledOnly = false

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)

            if entry.tasks.isEmpty {
                Spacer()
                Label(
                    scheduledOnly ? "Nothing scheduled" : "All clear",
                    systemImage: scheduledOnly ? "calendar.badge.checkmark" : "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    TaskWidgetRow(task: task, showsDetail: family != .systemSmall)
                    if task.id != entry.tasks.prefix(limit).last?.id {
                        Divider().opacity(0.45)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Link(destination: URL(string: "orbit://tasks")!) {
                Text(scheduledOnly ? (family == .systemSmall ? "DUE" : "SCHEDULED") : "TO DO")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text("\(entry.tasks.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Link(destination: URL(string: "orbit://voice")!) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
            }
            .accessibilityLabel("Open Orbit live voice")
            Link(destination: URL(string: "orbit://tasks/new")!) {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Add To Do")
        }
        .foregroundStyle(.primary)
    }
}

private struct TaskWidgetRow: View {
    @Environment(\.widgetFamily) private var family
    let task: TaskItem
    var showsDetail: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            Link(destination: URL(string: "orbit://tasks/\(task.id.uuidString)")!) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if showsDetail, let detail = detail(task) {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, family == .systemLarge ? 5 : 3)
    }

    private func detail(_ task: TaskItem) -> String? {
        if task.isOverdue { return "Overdue" }
        if let date = task.dueDate {
            return date.formatted(
                date: task.isDueToday ? .omitted : .abbreviated,
                time: .shortened
            )
        }
        return task.source == .manual ? "No date" : task.source.label
    }
}

struct OrbitTasksWidget: Widget {
    let kind = "OrbitTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Orbit To Do")
        .description("Your unified To Do list with readable text and quick actions.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Keeps the former widget kind so existing installations upgrade in place,
/// but now reads scheduled items from the same unified To Do store.
struct OrbitScheduledWidget: Widget {
    let kind = "OrbitRemindersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduledTasksProvider()) { entry in
            TasksWidgetView(entry: entry, scheduledOnly: true)
        }
        .configurationDisplayName("Orbit Scheduled")
        .description("Dated To Do items that also sync with Apple Calendar.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct AssistantEntry: TimelineEntry {
    let date: Date
}

private struct AssistantProvider: TimelineProvider {
    func placeholder(in context: Context) -> AssistantEntry { AssistantEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        completion(Timeline(entries: [AssistantEntry(date: .now)], policy: .never))
    }
}

private struct AssistantWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "waveform.and.mic")
                        .font(.title3.weight(.bold))
                        .widgetAccentable()
                }
                .widgetURL(URL(string: "orbit://voice")!)
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ask Orbit").font(.headline)
                        Text("Chat or talk live").font(.caption)
                    }
                }
                .widgetURL(URL(string: "orbit://assistant")!)
            case .systemMedium:
                mediumAssistant
            default:
                smallAssistant
            }
        }
        .containerBackground(.background, for: .widget)
        .accessibilityLabel("Ask Orbit")
    }

    private var smallAssistant: some View {
        Link(destination: URL(string: "orbit://assistant")!) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2.weight(.bold))
                Text("Ask Orbit")
                    .font(.title3.weight(.bold))
                Text("Continue your conversation")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Label("Open chat", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var mediumAssistant: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                Text("Ask Orbit")
                    .font(.title2.weight(.bold))
                Text("Pick up your chat or start a hands-free conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                assistantLink("Chat", systemImage: "bubble.left.fill", destination: "orbit://assistant")
                assistantLink("Live", systemImage: "waveform", destination: "orbit://voice")
            }
            .frame(width: 105)
        }
    }

    private func assistantLink(
        _ title: String,
        systemImage: String,
        destination: String
    ) -> some View {
        Link(destination: URL(string: destination)!) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(.primary.opacity(0.1), in: Capsule())
        }
        .foregroundStyle(.primary)
    }
}

/// Retains the original kind so an installed lock-screen voice widget upgrades
/// into the richer Ask Orbit widget without needing to be added again.
struct OrbitAssistantWidget: Widget {
    let kind = "OrbitVoiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AssistantProvider()) { _ in
            AssistantWidgetView()
        }
        .configurationDisplayName("Ask Orbit")
        .description("Open persistent chat or start a live voice conversation.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// A one-tap Control Center launcher that follows the same deep-link route as
/// Orbit's in-app live voice control. Control widgets are available on iOS 18+;
/// the rest of this extension continues to support iOS 17.
@available(iOS 18.0, *)
struct OrbitVoiceControl: ControlWidget {
    static let kind = "OrbitVoiceControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenOrbitVoiceIntent()) {
                Label("Orbit Voice", systemImage: "waveform.and.mic")
            }
        }
        .displayName("Orbit Voice")
        .description("Open Orbit directly in live voice mode.")
    }
}

@main
struct OrbitTasksWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbitTasksWidget()
        OrbitScheduledWidget()
        OrbitAssistantWidget()
        if #available(iOS 18.0, *) {
            OrbitVoiceControl()
        }
    }
}

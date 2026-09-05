import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget design system

/// Widget-local tokens mirror Orbit's black canvas and signal-red brand without
/// coupling the extension to app-only UI types.
private enum OrbitWidgetTheme {
    static let canvas = Color(red: 7 / 255, green: 7 / 255, blue: 8 / 255)
    static let surface = Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    static let elevated = Color(red: 28 / 255, green: 28 / 255, blue: 33 / 255)
    static let border = Color(red: 48 / 255, green: 48 / 255, blue: 55 / 255)
    static let separator = Color(red: 37 / 255, green: 37 / 255, blue: 43 / 255)
    static let text = Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)
    static let secondaryText = Color(red: 178 / 255, green: 178 / 255, blue: 188 / 255)
    static let mutedText = Color(red: 126 / 255, green: 126 / 255, blue: 137 / 255)
    static let red = Color(red: 243 / 255, green: 38 / 255, blue: 62 / 255)
    static let brightRed = Color(red: 1, green: 53 / 255, blue: 75 / 255)
    static let coral = Color(red: 1, green: 102 / 255, blue: 117 / 255)

    static let brandGradient = LinearGradient(
        colors: [brightRed, Color(red: 212 / 255, green: 20 / 255, blue: 44 / 255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct OrbitWidgetBackground: View {
    var body: some View {
        ZStack {
            OrbitWidgetTheme.canvas

            LinearGradient(
                colors: [OrbitWidgetTheme.surface.opacity(0.96), OrbitWidgetTheme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(OrbitWidgetTheme.red.opacity(0.16))
                .frame(width: 190, height: 190)
                .blur(radius: 44)
                .offset(x: 105, y: -100)

            LinearGradient(
                colors: [Color.white.opacity(0.055), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}

private struct OrbitBrandMark: View {
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                .fill(OrbitWidgetTheme.brandGradient)
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: compact ? 1.4 : 1.8)
                .padding(compact ? 5 : 7)
            Circle()
                .fill(Color.white)
                .frame(width: compact ? 3 : 4, height: compact ? 3 : 4)
                .offset(x: compact ? 4 : 5, y: compact ? -4 : -5)
        }
        .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
        .accessibilityHidden(true)
    }
}

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
                .padding(.bottom, family == .systemSmall ? 9 : 11)

            if entry.tasks.isEmpty {
                emptyState
            } else {
                let visibleTasks = Array(entry.tasks.prefix(limit))
                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                    TaskWidgetRow(task: task, showsDetail: family != .systemSmall)
                    if index < visibleTasks.count - 1 {
                        Rectangle()
                            .fill(OrbitWidgetTheme.separator)
                            .frame(height: 1)
                            .padding(.leading, 28)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            OrbitWidgetBackground()
        }
    }

    private var header: some View {
        HStack(spacing: family == .systemSmall ? 5 : 8) {
            Link(destination: URL(string: "orbit://tasks")!) {
                HStack(spacing: 7) {
                    if family != .systemSmall {
                        OrbitBrandMark(compact: true)
                    }
                    Text(scheduledOnly ? (family == .systemSmall ? "DUE" : "SCHEDULED") : "TO DO")
                        .font((family == .systemSmall ? Font.caption2 : Font.caption).weight(.heavy))
                        .tracking(0.8)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(OrbitWidgetTheme.text)
            Spacer(minLength: family == .systemSmall ? 2 : 4)
            Text("\(entry.tasks.count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(OrbitWidgetTheme.secondaryText)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 22)
                .background(OrbitWidgetTheme.elevated, in: Capsule())
                .overlay(Capsule().strokeBorder(OrbitWidgetTheme.border, lineWidth: 0.75))
            Link(destination: URL(string: "orbit://voice")!) {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(OrbitWidgetTheme.secondaryText)
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel("Open Orbit live voice")
            Button(intent: OpenOrbitIntent(target: .quickTaskCapture)) {
                Image(systemName: "plus")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(OrbitWidgetTheme.brandGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick add To Do")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(OrbitWidgetTheme.red.opacity(0.13))
                Circle()
                    .strokeBorder(OrbitWidgetTheme.red.opacity(0.5), lineWidth: 1)
                Image(systemName: scheduledOnly ? "calendar.badge.checkmark" : "checkmark")
                    .font(.system(size: family == .systemSmall ? 16 : 18, weight: .bold))
                    .foregroundStyle(OrbitWidgetTheme.coral)
            }
            .frame(width: family == .systemSmall ? 36 : 42, height: family == .systemSmall ? 36 : 42)

            Text(scheduledOnly ? "Nothing scheduled" : "You're all clear")
                .font((family == .systemSmall ? Font.subheadline : Font.headline).weight(.bold))
                .foregroundStyle(OrbitWidgetTheme.text)
                .lineLimit(1)

            if family != .systemSmall {
                Text(scheduledOnly ? "Dated tasks will appear here." : "New tasks will show up right here.")
                    .font(.caption)
                    .foregroundStyle(OrbitWidgetTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskWidgetRow: View {
    @Environment(\.widgetFamily) private var family
    let task: TaskItem
    var showsDetail: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                ZStack {
                    Circle()
                        .fill(OrbitWidgetTheme.red.opacity(0.08))
                    Circle()
                        .strokeBorder(OrbitWidgetTheme.red.opacity(0.82), lineWidth: 1.4)
                    Circle()
                        .fill(OrbitWidgetTheme.red)
                        .frame(width: 4, height: 4)
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            Link(destination: URL(string: "orbit://tasks/\(task.id.uuidString)")!) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OrbitWidgetTheme.text)
                        .lineLimit(1)
                    if showsDetail, let detail = detail(task) {
                        HStack(spacing: 4) {
                            if task.isOverdue {
                                Circle()
                                    .fill(OrbitWidgetTheme.red)
                                    .frame(width: 4, height: 4)
                            }
                            Text(detail)
                                .font(.caption2.weight(task.isOverdue ? .semibold : .regular))
                                .foregroundStyle(
                                    task.isOverdue ? OrbitWidgetTheme.coral : OrbitWidgetTheme.secondaryText
                                )
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, family == .systemLarge ? 5 : 4)
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
                    Circle()
                        .strokeBorder(.primary.opacity(0.45), lineWidth: 1)
                        .padding(5)
                        .widgetAccentable()
                    Image(systemName: "waveform")
                        .font(.headline.weight(.bold))
                }
                .widgetAccentable()
                .widgetURL(URL(string: "orbit://voice")!)
            case .accessoryRectangular:
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.primary.opacity(0.14))
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                    }
                    .frame(width: 28, height: 28)
                    .widgetAccentable()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Ask Orbit")
                            .font(.headline)
                        Text("Chat or talk live")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .widgetURL(URL(string: "orbit://assistant")!)
            case .systemMedium:
                mediumAssistant
            default:
                smallAssistant
            }
        }
        .containerBackground(for: .widget) {
            if isAccessoryFamily {
                Color.clear
            } else {
                OrbitWidgetBackground()
            }
        }
        .accessibilityLabel("Ask Orbit")
    }

    private var isAccessoryFamily: Bool {
        family == .accessoryCircular || family == .accessoryRectangular
    }

    private var smallAssistant: some View {
        Link(destination: URL(string: "orbit://assistant")!) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    OrbitBrandMark()
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OrbitWidgetTheme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(OrbitWidgetTheme.elevated, in: Circle())
                        .overlay(Circle().strokeBorder(OrbitWidgetTheme.border, lineWidth: 0.75))
                }

                Spacer(minLength: 8)

                Text("ASK ORBIT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.1)
                    .foregroundStyle(OrbitWidgetTheme.coral)
                Text("Your day,\none question away.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(OrbitWidgetTheme.text)
                    .lineLimit(2)
                    .padding(.top, 3)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Circle()
                        .fill(OrbitWidgetTheme.red)
                        .frame(width: 6, height: 6)
                    Text("Chat ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OrbitWidgetTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var mediumAssistant: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    OrbitBrandMark()
                    Text("ORBIT")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(OrbitWidgetTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text("What do you\nneed right now?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(OrbitWidgetTheme.text)
                    .lineLimit(2)

                Text("Chat or start a hands-free conversation.")
                    .font(.caption)
                    .foregroundStyle(OrbitWidgetTheme.secondaryText)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                assistantLink(
                    "Open chat",
                    systemImage: "bubble.left.fill",
                    destination: "orbit://assistant",
                    isPrimary: true
                )
                assistantLink(
                    "Live voice",
                    systemImage: "waveform",
                    destination: "orbit://voice",
                    isPrimary: false
                )
            }
            .frame(width: 118)
        }
    }

    private func assistantLink(
        _ title: String,
        systemImage: String,
        destination: String,
        isPrimary: Bool
    ) -> some View {
        Link(destination: URL(string: destination)!) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
            }
                .foregroundStyle(isPrimary ? Color.white : OrbitWidgetTheme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 11)
                .background {
                    if isPrimary {
                        OrbitWidgetTheme.brandGradient
                    } else {
                        OrbitWidgetTheme.elevated
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isPrimary ? Color.white.opacity(0.14) : OrbitWidgetTheme.border,
                            lineWidth: 0.75
                        )
                }
        }
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
            ControlWidgetButton(action: OpenOrbitIntent()) {
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

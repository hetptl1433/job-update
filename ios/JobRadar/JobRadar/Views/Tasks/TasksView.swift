import SwiftUI

struct TasksView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case tasks = "To Do"
        case reminders = "Reminders"
        var id: String { rawValue }
    }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    @EnvironmentObject private var reminders: ReminderRepository
    @State private var editing: TaskItem?
    @State private var editingReminder: ReminderItem?
    @State private var showingCompleted = false
    @State private var searchText = ""
    @State private var mode: Mode = .tasks

    private var open: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.prioritizedOpen.filter {
            query.isEmpty || "\($0.title) \($0.notes)".lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .tasks {
                        taskSection("To do", items: open)
                        if !tasks.suggestions.isEmpty { suggestionsSection }
                        if !tasks.completed.isEmpty { completedSection }
                    } else {
                        remindersSection
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Tasks")
            .searchable(text: $searchText, prompt: "Search tasks")
            .refreshable { await app.refreshTasks() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if mode == .tasks { editing = TaskItem(title: "") }
                        else { editingReminder = ReminderItem(title: "", fireDate: .now.addingTimeInterval(3_600)) }
                    } label: { Image(systemName: "plus") }
                        .tint(AppTheme.primaryText)
                }
            }
            .sheet(item: $editing) { item in
                TaskEditor(item: item) { saved in
                    if tasks.tasks.contains(where: { $0.id == saved.id }) { tasks.update(saved) }
                    else { tasks.add(saved) }
                }
            }
            .sheet(item: $editingReminder) { item in
                ReminderEditor(item: item) { saved in
                    if reminders.reminders.contains(where: { $0.id == saved.id }) { reminders.update(saved) }
                    else { reminders.add(saved) }
                    Task { await app.refreshCalendar(presentErrors: false) }
                }
            }
            .onAppear {
                tasks.reload()
                reminders.reload()
                openDeepLinkedTask()
                openDeepLinkedReminder()
            }
            .onChange(of: tasks.openTaskID) { _, _ in openDeepLinkedTask() }
            .onChange(of: reminders.openReminderID) { _, _ in openDeepLinkedReminder() }
            .onChange(of: tasks.createTaskRequested) { _, requested in
                guard requested else { return }
                mode = .tasks
                editing = TaskItem(title: "")
                tasks.createTaskRequested = false
            }
            .onChange(of: reminders.createReminderRequested) { _, requested in
                guard requested else { return }
                mode = .reminders
                editingReminder = ReminderItem(title: "", fireDate: .now.addingTimeInterval(3_600))
                reminders.createReminderRequested = false
            }
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, items: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: title)
            if items.isEmpty {
                InfoStateView(systemImage: "checkmark.circle", title: "Nothing to do",
                              message: "Add a task or accept an AI suggestion from your email.",
                              actionTitle: "Add task") { editing = TaskItem(title: "") }
                    .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TaskRow(item: item, onToggle: { tasks.toggle(item) })
                            .contentShape(Rectangle())
                            .onTapGesture { editing = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { tasks.delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        if index < items.count - 1 { Divider().overlay(AppTheme.separator) }
                    }
                }
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Suggestions · \(tasks.suggestions.count)").sectionLabel()
            ForEach(tasks.suggestions) { item in
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Button { tasks.acceptSuggestion(item) } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Button { tasks.dismissSuggestion(item) } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(AppTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
                .overlay(alignment: .bottom) { Divider().overlay(AppTheme.separator) }
            }
        }
    }

    private var completedSection: some View {
        DisclosureGroup(isExpanded: $showingCompleted) {
            VStack(spacing: 0) {
                ForEach(tasks.completed) { item in
                    TaskRow(item: item, onToggle: { tasks.toggle(item) })
                        .contentShape(Rectangle()).onTapGesture { editing = item }
                }
            }
        } label: {
            Text("Completed (\(tasks.completed.count))").sectionLabel()
        }
        .tint(AppTheme.secondaryText)
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Upcoming reminders")
            if let error = reminders.calendarSyncError {
                Label(error, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            if reminders.open.isEmpty {
                InfoStateView(
                    systemImage: "bell",
                    title: "No reminders",
                    message: "Reminders are separate from To Do and sync with Apple Calendar.",
                    actionTitle: "Add reminder"
                ) { editingReminder = ReminderItem(title: "", fireDate: .now.addingTimeInterval(3_600)) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(reminders.open.enumerated()), id: \.element.id) { index, item in
                        ReminderRow(item: item, onToggle: { reminders.toggle(item) })
                            .contentShape(Rectangle())
                            .onTapGesture { editingReminder = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { reminders.delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        if index < reminders.open.count - 1 { Divider().overlay(AppTheme.separator) }
                    }
                }
            }
        }
    }

    private func openDeepLinkedTask() {
        if tasks.createTaskRequested {
            mode = .tasks
            editing = TaskItem(title: "")
            tasks.createTaskRequested = false
            return
        }
        guard let id = tasks.openTaskID,
              let item = tasks.tasks.first(where: { $0.id == id }) else { return }
        editing = item
        tasks.openTaskID = nil
    }

    private func openDeepLinkedReminder() {
        if reminders.createReminderRequested {
            mode = .reminders
            editingReminder = ReminderItem(title: "", fireDate: .now.addingTimeInterval(3_600))
            reminders.createReminderRequested = false
            return
        }
        guard let id = reminders.openReminderID,
              let item = reminders.reminders.first(where: { $0.id == id }) else { return }
        mode = .reminders
        editingReminder = item
        reminders.openReminderID = nil
    }
}

struct TaskRow: View {
    let item: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? AppTheme.success : AppTheme.primaryText)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.isCompleted ? AppTheme.tertiaryText : AppTheme.primaryText)
                    .strikethrough(item.isCompleted)
                HStack(spacing: 5) {
                    if item.isOverdue { Text("Overdue").foregroundStyle(AppTheme.destructive) }
                    else if let due = item.dueDate {
                        Text(due.formatted(date: item.isDueToday ? .omitted : .abbreviated, time: .shortened))
                    }
                    if item.source != .manual {
                        if item.dueDate != nil { Text("·") }
                        Text(item.source.label)
                    }
                    if item.priority == .high { Image(systemName: "exclamationmark") }
                    if item.dueDate != nil, item.effectiveAlertStyle != .none {
                        Image(systemName: item.effectiveAlertStyle == .alarm ? "alarm" : "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State var item: TaskItem
    let onSave: (TaskItem) -> Void
    @State private var hasDueDate: Bool

    init(item: TaskItem, onSave: @escaping (TaskItem) -> Void) {
        _item = State(initialValue: item)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $item.title, axis: .vertical)
                    TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(2...6)
                }
                Section("Schedule") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: Binding(
                            get: { item.dueDate ?? .now }, set: { item.dueDate = $0 }
                        ))
                        Picker("Alert", selection: Binding(
                            get: { item.effectiveAlertStyle },
                            set: { item.alertStyle = $0 }
                        )) {
                            ForEach(TaskAlertStyle.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Text(hasDueDate
                         ? "Timed To Dos are added to Apple Calendar. Alarm is the default; on iOS 17–25 it falls back to a sound notification."
                         : "Without a time, this stays only in your To Do list.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Section("Priority") {
                    Picker("Priority", selection: $item.priority) {
                        ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if item.source != .manual {
                    Section("Source") { LabeledContent("Created from", value: item.source.label) }
                }
            }
            .navigationTitle(item.title.isEmpty ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasDueDate { item.dueDate = nil }
                        let needsCalendarAccess = hasDueDate && !app.connections.appleCalendarConnected
                        onSave(item); dismiss()
                        if needsCalendarAccess { Task { await app.connectAppleCalendar() } }
                    }
                    .fontWeight(.semibold)
                    .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? AppTheme.success : AppTheme.primaryText)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.fireDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Image(systemName: alertSystemImage)
                .font(.caption).foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private var alertSystemImage: String {
        switch item.effectiveAlertStyle {
        case .alarm: "alarm"
        case .notification: "bell"
        case .none: "bell.slash"
        }
    }
}

private struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ReminderItem
    let onSave: (ReminderItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Remind me to…", text: $item.title, axis: .vertical)
                    TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(2...5)
                    DatePicker("Date and time", selection: $item.fireDate)
                    Picker("Alert", selection: Binding(
                        get: { item.effectiveAlertStyle },
                        set: { item.alertStyle = $0 }
                    )) {
                        ForEach(TaskAlertStyle.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Label("This reminder creates one linked Apple Calendar event. Moving or renaming that event updates the reminder.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle(item.title.isEmpty ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(item); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

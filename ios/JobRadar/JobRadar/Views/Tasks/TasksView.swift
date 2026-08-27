import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    @State private var editing: TaskItem?
    @State private var showingCompleted = false
    @State private var searchText = ""

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
                    if let error = tasks.calendarSyncError {
                        Label(error, systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    taskSection("To Do", items: open)
                    if !tasks.suggestions.isEmpty { suggestionsSection }
                    if !tasks.completed.isEmpty { completedSection }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("To Do")
            .searchable(text: $searchText, prompt: "Search To Do")
            .refreshable { await app.refreshTasks() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = TaskItem(title: "") } label: { Image(systemName: "plus") }
                        .tint(AppTheme.primaryText)
                }
            }
            .sheet(item: $editing) { item in
                TaskEditor(item: item) { saved in
                    if tasks.tasks.contains(where: { $0.id == saved.id }) { tasks.update(saved) }
                    else { tasks.add(saved) }
                }
            }
            .onAppear {
                tasks.reload()
                openDeepLinkedTask()
            }
            .onChange(of: tasks.openTaskID) { _, _ in openDeepLinkedTask() }
            .onChange(of: tasks.createTaskRequested) { _, requested in
                guard requested else { return }
                editing = TaskItem(title: "")
                tasks.createTaskRequested = false
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
                    Button { app.acceptTaskSuggestion(item) } label: {
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
                    Button { app.dismissTaskSuggestion(item) } label: {
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

    private func openDeepLinkedTask() {
        if tasks.createTaskRequested {
            editing = TaskItem(title: "")
            tasks.createTaskRequested = false
            return
        }
        guard let id = tasks.openTaskID,
              let item = tasks.tasks.first(where: { $0.id == id }) else { return }
        editing = item
        tasks.openTaskID = nil
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
                    Toggle("Add date & time", isOn: Binding(
                        get: { hasDueDate },
                        set: { enabled in
                            hasDueDate = enabled
                            if enabled, item.dueDate == nil {
                                item.dueDate = Calendar.current.date(
                                    byAdding: .hour,
                                    value: 1,
                                    to: .now
                                ) ?? .now.addingTimeInterval(3_600)
                            } else if !enabled {
                                item.dueDate = nil
                            }
                        }
                    ))
                    if hasDueDate {
                        DatePicker("Due", selection: Binding(
                            get: { item.dueDate ?? .now }, set: { item.dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        Picker("Alert", selection: Binding(
                            get: { item.effectiveAlertStyle },
                            set: { item.alertStyle = $0 }
                        )) {
                            ForEach(TaskAlertStyle.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Text(hasDueDate
                         ? "This To Do will create one linked Apple Calendar event. Alarm is the default; on iOS 17–25 it falls back to a sound notification."
                         : "Without a date and time, this stays only in your To Do list.")
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
            .navigationTitle(item.title.isEmpty ? "New To Do" : "Edit To Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasDueDate { item.dueDate = nil }
                        if hasDueDate, item.dueDate == nil {
                            item.dueDate = .now.addingTimeInterval(3_600)
                        }
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

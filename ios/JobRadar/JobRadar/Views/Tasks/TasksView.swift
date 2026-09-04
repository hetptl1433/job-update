import SwiftUI

struct TasksView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tasks: TaskRepository
    @State private var editing: TaskItem?
    @State private var showingCompleted = false
    @State private var searchText = ""
    @State private var quickCaptureTitle = ""
    @State private var schedulingTask: TaskItem?
    @State private var completingTaskIDs: Set<UUID> = []
    @State private var hiddenTaskIDs: Set<UUID> = []
    @State private var undoAction: TodoUndoAction?
    @State private var undoToken: UUID?
    @State private var successFeedback = 0
    @State private var selectionFeedback = 0
    @State private var deletionFeedback = 0
    @FocusState private var quickCaptureFocused: Bool

    private enum TodoUndoAction {
        case completed(TaskItem)
        case deleted(TaskItem)

        var message: String {
            switch self {
            case let .completed(item): "Completed “\(item.title)”"
            case let .deleted(item): "Deleted “\(item.title)”"
            }
        }
    }

    private enum QuickSchedule: Equatable {
        case today, tomorrow, nextWeek, anytime
    }

    private var open: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.prioritizedOpen.filter {
            !hiddenTaskIDs.contains($0.id)
                && (query.isEmpty || "\($0.title) \($0.notes)".lowercased().contains(query))
        }
    }

    private var overdue: [TaskItem] {
        open.filter(\.isOverdue).sorted(by: dueDateAscending)
    }
    private var dueToday: [TaskItem] {
        open.filter { !$0.isOverdue && $0.isDueToday }.sorted(by: dueDateAscending)
    }
    private var upcoming: [TaskItem] {
        open.filter { $0.dueDate != nil && !$0.isOverdue && !$0.isDueToday }
            .sorted(by: dueDateAscending)
    }
    private var anytime: [TaskItem] {
        open.filter { $0.dueDate == nil }.sorted {
            if $0.priority != $1.priority { return priorityRank($0.priority) < priorityRank($1.priority) }
            return $0.updatedAt > $1.updatedAt
        }
    }
    private var visibleCompleted: [TaskItem] {
        tasks.completed.filter { !hiddenTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { quickCapture }

                if let error = tasks.calendarSyncError {
                    Label(error, systemImage: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(AppTheme.secondarySurface)
                        .listRowSeparator(.hidden)
                        .accessibilityLabel("Calendar sync error. \(error)")
                }

                if open.isEmpty {
                    Section {
                        InfoStateView(
                            systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                            title: searchText.isEmpty ? "You're all caught up" : "No matching To Dos",
                            message: searchText.isEmpty
                                ? "Capture something above or accept an AI suggestion from your email."
                                : "Try a different title or keyword.",
                            actionTitle: searchText.isEmpty ? "Add details" : nil
                        ) {
                            editing = TaskItem(title: "")
                        }
                        .padding(.vertical, AppTheme.Spacing.lg)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                taskSection(
                    "Overdue",
                    subtitle: "Needs attention",
                    systemImage: "exclamationmark.circle.fill",
                    accent: AppTheme.destructive,
                    items: overdue
                )
                taskSection(
                    "Today",
                    subtitle: "Your focus now",
                    systemImage: "sun.max.fill",
                    accent: AppTheme.accent,
                    items: dueToday
                )
                taskSection(
                    "Upcoming",
                    subtitle: "Planned ahead",
                    systemImage: "calendar",
                    accent: AppTheme.info,
                    items: upcoming
                )
                taskSection(
                    "Anytime",
                    subtitle: "No due date",
                    systemImage: "tray.full.fill",
                    accent: AppTheme.secondaryText,
                    items: anytime
                )

                if !tasks.suggestions.isEmpty { suggestionsSection }
                if !visibleCompleted.isEmpty { completedSection }
            }
            .listStyle(.plain)
            .listSectionSpacing(AppTheme.Spacing.xl)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("To Do")
            .searchable(text: $searchText, prompt: "Search To Do")
            .refreshable { await app.refreshTasks() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = TaskItem(title: "") } label: { Image(systemName: "plus") }
                        .tint(AppTheme.primaryText)
                        .accessibilityLabel("Create To Do with details")
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
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { commitPendingDeletionAndDismissUndo() }
            }
            .onDisappear { commitPendingDeletionAndDismissUndo() }
            .confirmationDialog(
                schedulingTask.map { "Schedule “\($0.title)”" } ?? "Schedule To Do",
                isPresented: Binding(
                    get: { schedulingTask != nil },
                    set: { if !$0 { schedulingTask = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Today") { scheduleSelectedTask(.today) }
                Button("Tomorrow") { scheduleSelectedTask(.tomorrow) }
                Button("Next Monday") { scheduleSelectedTask(.nextWeek) }
                Button("Pick date & time…") { editScheduledTask() }
                Button("Anytime · No due date") { scheduleSelectedTask(.anytime) }
                Button("Cancel", role: .cancel) { schedulingTask = nil }
            } message: {
                Text("Choose when this To Do should appear.")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let undoAction {
                    undoBanner(for: undoAction)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: undoAction != nil)
            .sensoryFeedback(.success, trigger: successFeedback)
            .sensoryFeedback(.selection, trigger: selectionFeedback)
            .sensoryFeedback(
                .impact(weight: .light, intensity: 0.65),
                trigger: deletionFeedback
            )
        }
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text("QUICK CAPTURE")
                    .sectionLabel()
                Spacer()
                Text("Press return to add")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .opacity(dynamicTypeSize.isAccessibilitySize ? 0 : 1)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppTheme.Spacing.sm) { quickCaptureField; quickCaptureButton }
                } else {
                    HStack(spacing: AppTheme.Spacing.sm) { quickCaptureField; quickCaptureButton }
                }
            }
        }
        .cardSurface(padding: AppTheme.Spacing.lg, radius: AppTheme.Radius.lg)
        .listRowInsets(EdgeInsets(
            top: AppTheme.Spacing.md,
            leading: AppTheme.Spacing.lg,
            bottom: 0,
            trailing: AppTheme.Spacing.lg
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var quickCaptureField: some View {
        TextField("What needs to be done?", text: $quickCaptureTitle)
            .focused($quickCaptureFocused)
            .submitLabel(.done)
            .textInputAutocapitalization(.sentences)
            .onSubmit(addQuickCapture)
            .font(.body.weight(.medium))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 48)
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(quickCaptureFocused ? AppTheme.accent : AppTheme.border, lineWidth: 1)
            }
            .accessibilityLabel("Quick capture title")
    }

    private var quickCaptureButton: some View {
        Button(action: addQuickCapture) {
            Label("Add", systemImage: "arrow.up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.onAccent)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minWidth: 62, minHeight: 48)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .accessibilityLabel("Add To Do")
        .accessibilityHint("Adds this item without a due date")
    }

    @ViewBuilder
    private func taskSection(
        _ title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        items: [TaskItem]
    ) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    TaskRow(
                        item: item,
                        onToggle: { complete(item) },
                        isCompleting: completingTaskIDs.contains(item.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editing = item }
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AppTheme.Spacing.lg,
                        bottom: 0,
                        trailing: AppTheme.Spacing.lg
                    ))
                    .listRowBackground(AppTheme.primarySurface)
                    .listRowSeparatorTint(AppTheme.separator)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { schedulingTask = item } label: {
                            Label("Schedule", systemImage: "calendar.badge.clock")
                        }
                        .tint(AppTheme.accent)
                        Button { schedule(item, as: .tomorrow) } label: {
                            Label("Tomorrow", systemImage: "sunrise.fill")
                        }
                        .tint(AppTheme.info)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteWithUndo(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityAction(named: "Schedule") { schedulingTask = item }
                    .accessibilityAction(named: "Edit") { editing = item }
                    .accessibilityAction(named: "Delete") { deleteWithUndo(item) }
                }
            } header: {
                TodoSectionHeader(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    accent: accent,
                    count: items.count
                )
                .textCase(nil)
            }
        }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(tasks.suggestions) { item in
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Button {
                        app.acceptTaskSuggestion(item)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept suggestion \(item.title)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Button {
                        app.dismissTaskSuggestion(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss suggestion \(item.title)")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
                .listRowBackground(AppTheme.primarySurface)
                .listRowSeparatorTint(AppTheme.separator)
            }
        } header: {
            TodoSectionHeader(
                title: "Suggestions",
                subtitle: "Found from your activity",
                systemImage: "sparkles",
                accent: AppTheme.purple,
                count: tasks.suggestions.count
            )
            .textCase(nil)
        }
    }

    private var completedSection: some View {
        Section {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showingCompleted.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Text("\(visibleCompleted.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .rotationEffect(.degrees(showingCompleted ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(AppTheme.secondarySurface)
            .accessibilityLabel("Completed, \(visibleCompleted.count) items")
            .accessibilityValue(showingCompleted ? "Expanded" : "Collapsed")

            if showingCompleted {
                ForEach(visibleCompleted) { item in
                    TaskRow(item: item, onToggle: { reopen(item) })
                        .contentShape(Rectangle())
                        .onTapGesture { editing = item }
                        .listRowBackground(AppTheme.primarySurface)
                        .listRowSeparatorTint(AppTheme.separator)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteWithUndo(item) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: "Edit") { editing = item }
                        .accessibilityAction(named: "Delete") { deleteWithUndo(item) }
                }
            }
        }
    }

    private func addQuickCapture() {
        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard tasks.add(TaskItem(title: title)) else { return }
        successFeedback += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            quickCaptureTitle = ""
        }
        quickCaptureFocused = true
    }

    private func complete(_ item: TaskItem) {
        guard !completingTaskIDs.contains(item.id) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68)) {
            _ = completingTaskIDs.insert(item.id)
        }

        let delay = reduceMotion ? 0 : 0.24
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completingTaskIDs.remove(item.id)
            guard let current = tasks.tasks.first(where: { $0.id == item.id }),
                  !current.isCompleted else { return }
            let didComplete = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                tasks.setCompletion(current.id, isCompleted: true)
            }
            if didComplete {
                successFeedback += 1
                presentUndo(.completed(item))
            }
        }
    }

    private func reopen(_ item: TaskItem) {
        let didReopen = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            tasks.setCompletion(item.id, isCompleted: false)
        }
        if didReopen { selectionFeedback += 1 }
    }

    private func deleteWithUndo(_ item: TaskItem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            _ = hiddenTaskIDs.insert(item.id)
        }
        deletionFeedback += 1
        presentUndo(.deleted(item))
    }

    private func presentUndo(_ action: TodoUndoAction) {
        // Deletion is committed only after the undo window. This avoids racing
        // the repository's asynchronous alert cancellation with a restore.
        commitPendingDeletion()

        let token = UUID()
        undoAction = action
        undoToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard undoToken == token else { return }
            commitPendingDeletionAndDismissUndo()
        }
    }

    private func performUndo() {
        guard let action = undoAction else { return }
        undoToken = nil
        let didUndo: Bool
        switch action {
        case let .completed(item):
            didUndo = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                tasks.setCompletion(item.id, isCompleted: false)
            }
        case let .deleted(item):
            didUndo = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                hiddenTaskIDs.remove(item.id) != nil
            }
        }
        if didUndo { selectionFeedback += 1 }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            undoAction = nil
        }
    }

    private func commitPendingDeletion() {
        guard case let .deleted(item) = undoAction else { return }
        tasks.delete(item)
        hiddenTaskIDs.remove(item.id)
    }

    private func commitPendingDeletionAndDismissUndo() {
        commitPendingDeletion()
        undoToken = nil
        undoAction = nil
    }

    private func scheduleSelectedTask(_ choice: QuickSchedule) {
        guard let item = schedulingTask else { return }
        schedulingTask = nil
        schedule(item, as: choice)
    }

    private func editScheduledTask() {
        guard let item = schedulingTask else { return }
        schedulingTask = nil
        editing = item
    }

    private func schedule(_ item: TaskItem, as choice: QuickSchedule) {
        let didSchedule = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            tasks.reschedule(item, to: scheduledDate(for: choice))
        }
        if didSchedule { selectionFeedback += 1 }
    }

    private func scheduledDate(for choice: QuickSchedule) -> Date? {
        guard choice != .anytime else { return nil }
        let calendar = Calendar.current
        let now = Date.now

        switch choice {
        case .today:
            let preferred = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
            guard preferred <= now else { return preferred }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(86_400)
            let endOfToday = tomorrow.addingTimeInterval(-1)
            return endOfToday > now ? min(now.addingTimeInterval(3_600), endOfToday) : now
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .nextWeek:
            let tomorrow = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            ) ?? now
            return calendar.nextDate(
                after: tomorrow,
                matching: DateComponents(hour: 9, minute: 0, second: 0, weekday: 2),
                matchingPolicy: .nextTime,
                direction: .forward
            ) ?? now.addingTimeInterval(604_800)
        case .anytime:
            return nil
        }
    }

    private func dueDateAscending(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        guard lhs.dueDate != rhs.dueDate else {
            if lhs.priority != rhs.priority { return priorityRank(lhs.priority) < priorityRank(rhs.priority) }
            return lhs.updatedAt > rhs.updatedAt
        }
        return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }

    private func undoBanner(for action: TodoUndoAction) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
            Text(action.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button("Undo", action: performUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .accessibilityElement(children: .contain)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: TaskItem
    let onToggle: () -> Void
    var isCompleting = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted || isCompleting ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted || isCompleting ? AppTheme.success : AppTheme.primaryText)
                    .font(.title3)
                    .scaleEffect(isCompleting ? 1.2 : 1)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(isCompleting)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.title) incomplete" : "Complete \(item.title)")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.isCompleted || isCompleting ? AppTheme.tertiaryText : AppTheme.primaryText)
                    .strikethrough(item.isCompleted || isCompleting)
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) { dueAndSourceMetadata }
                            HStack(spacing: 5) { taskSignalMetadata }
                        }
                    } else {
                        HStack(spacing: 5) {
                            dueAndSourceMetadata
                            taskSignalMetadata
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(minHeight: 58)
        .opacity(isCompleting ? 0.72 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: isCompleting)
    }

    @ViewBuilder
    private var dueAndSourceMetadata: some View {
        if item.isOverdue {
            Text("Overdue").foregroundStyle(AppTheme.destructive)
        } else if let due = item.dueDate {
            Text(due.formatted(date: item.isDueToday ? .omitted : .abbreviated, time: .shortened))
        }
        if item.source != .manual {
            if item.dueDate != nil { Text("·") }
            Text(item.source.label)
        }
    }

    @ViewBuilder
    private var taskSignalMetadata: some View {
        if item.priority == .high {
            Label("High priority", systemImage: "exclamationmark")
                .labelStyle(.iconOnly)
        }
        if item.dueDate != nil, item.effectiveAlertStyle != .none {
            Label(
                item.effectiveAlertStyle == .alarm ? "Alarm" : "Notification",
                systemImage: item.effectiveAlertStyle == .alarm ? "alarm" : "bell"
            )
            .labelStyle(.iconOnly)
        }
    }
}

private struct TodoSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let count: Int

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(accent)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(accent.opacity(0.12), in: Capsule())
                .accessibilityLabel("\(count) items")
        }
        .padding(.top, AppTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
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

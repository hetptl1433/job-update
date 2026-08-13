import SwiftUI
#if os(watchOS)
import WatchKit
#endif

private enum WatchRoute: Hashable {
    case voice
}

struct WatchRootView: View {
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WatchTasksView()
                .navigationDestination(for: WatchRoute.self) { route in
                    switch route {
                    case .voice:
                        WatchVoiceView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openVoice()
                        } label: {
                            Image(systemName: "waveform.circle.fill")
                        }
                        .accessibilityLabel("Talk to Orbit")
                        .accessibilityHint("Starts a live voice conversation")
                    }
                }
        }
        .onOpenURL(perform: handleOpenURL)
    }

    private func openVoice() {
        guard path.last != .voice else { return }
        path.append(.voice)
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "orbit-watch",
              url.host?.lowercased() == "voice" else { return }
        openVoice()
    }
}

struct WatchTasksView: View {
    @EnvironmentObject private var store: WatchTaskStore

    private var today: [WatchTaskSnapshotItem] {
        store.tasks.filter { $0.isOverdue() || $0.isDueToday() }
    }

    private var upcoming: [WatchTaskSnapshotItem] {
        store.tasks.filter { $0.dueDate != nil && !$0.isOverdue() && !$0.isDueToday() }
    }

    private var anytime: [WatchTaskSnapshotItem] {
        store.tasks.filter { $0.dueDate == nil }
    }

    var body: some View {
        List {
            if store.tasks.isEmpty {
                emptyState
            } else {
                taskSection("TODAY", tasks: today)
                taskSection("UPCOMING", tasks: upcoming)
                taskSection("ANYTIME", tasks: anytime)
            }

            Section {
                Button {
                    store.requestLatest()
                } label: {
                    Label(
                        store.isPhoneReachable ? "Refresh" : "Using saved tasks",
                        systemImage: store.isPhoneReachable ? "arrow.clockwise" : "iphone.slash"
                    )
                }
                .disabled(!store.isPhoneReachable)

                if let updatedAt = store.lastUpdatedAt {
                    Text("Updated \(updatedAt, style: .relative)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Orbit")
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [WatchTaskSnapshotItem]) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { task in
                    WatchTaskRow(task: task)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.lastUpdatedAt == nil ? "iphone.and.arrow.forward" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(store.lastUpdatedAt == nil ? Color.secondary : Color.green)
            Text(store.lastUpdatedAt == nil ? "Open Orbit on your iPhone to sync." : "All caught up")
                .font(.headline)
                .multilineTextAlignment(.center)
            if store.lastUpdatedAt == nil {
                Text("Your open To Dos will stay available here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
    }
}

private struct WatchVoiceView: View {
    @EnvironmentObject private var store: WatchTaskStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var realtime = OpenAIRealtimeSession()
    @State private var requestFailure: WatchVoiceFailure?
    @State private var lastTurnText = ""
    @State private var lifecycleMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                voiceOrb

                Text(statusText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                transcript

                if errorMessage != nil {
                    Button {
                        startConversation()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    liveControls
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.bottom, 4)
        }
        .navigationTitle("Voice")
        .task {
            startConversation()
        }
        .onChange(of: store.voiceRequestState) { _, state in
            handleVoiceRequestState(state)
        }
        .onChange(of: realtime.completedTurn) { _, turn in
            if let turn { lastTurnText = turn.text }
        }
        .onChange(of: realtime.state) { oldState, newState in
            guard oldState != .connected, newState == .connected else { return }
#if os(watchOS)
            WKInterfaceDevice.current().play(.start)
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            endConversation(forLifecycle: true)
        }
        .onDisappear {
            endConversation(forLifecycle: false)
        }
    }

    private var voiceOrb: some View {
        let activeLevel = realtime.isAssistantSpeaking
            ? realtime.outputAudioLevel
            : realtime.inputAudioLevel
        let pulse = CGFloat(min(max(activeLevel, 0), 1))

        return ZStack {
            Circle()
                .fill(orbColor.opacity(0.14))
                .frame(width: 90, height: 90)
                .scaleEffect(1 + pulse * 0.12)

            Circle()
                .stroke(orbColor.opacity(0.42), lineWidth: 2)
                .frame(width: 70, height: 70)
                .scaleEffect(1 + pulse * 0.08)

            Circle()
                .fill(orbColor.gradient)
                .frame(width: 54, height: 54)

            Image(systemName: orbSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeOut(duration: 0.12), value: pulse)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var transcript: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(transcriptText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(minHeight: 32, alignment: .top)
        }
    }

    private var liveControls: some View {
        HStack(spacing: 12) {
            Button {
                realtime.toggleMute()
            } label: {
                Image(systemName: realtime.isMuted ? "mic.slash.fill" : "mic.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(!realtime.isActive)
            .accessibilityLabel(realtime.isMuted ? "Unmute" : "Mute")

            Button(role: .destructive) {
                endConversation(forLifecycle: false)
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityLabel("End conversation")
        }
    }

    private var statusText: String {
        if requestFailure != nil || lifecycleMessage != nil { return "Couldn't connect" }
        if case .requesting = store.voiceRequestState { return "Getting ready…" }

        switch realtime.phase {
        case .idle: return "Getting ready…"
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .hearing: return "I hear you"
        case .thinking: return "Thinking…"
        case .speaking: return "Orbit is speaking"
        case .muted: return "Muted"
        case .failed: return "Couldn't connect"
        }
    }

    private var transcriptText: String {
        let assistant = realtime.liveAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assistant.isEmpty { return assistant }
        let user = realtime.liveUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return user }
        if !lastTurnText.isEmpty { return lastTurnText }
        return "Start talking when the orb says Listening."
    }

    private var errorMessage: String? {
        requestFailure?.message
            ?? lifecycleMessage
            ?? realtime.errorMessage
    }

    private var orbColor: Color {
        if errorMessage != nil { return .red }
        if realtime.isMuted { return .gray }
        if realtime.isAssistantSpeaking { return .purple }
        if realtime.isUserSpeaking { return .green }
        return .cyan
    }

    private var orbSymbol: String {
        if errorMessage != nil { return "exclamationmark" }
        if realtime.isMuted { return "mic.slash.fill" }
        if realtime.isAssistantSpeaking { return "speaker.wave.2.fill" }
        return "waveform"
    }

    private func startConversation() {
        realtime.disconnect()
        store.resetVoiceRequest()
        requestFailure = nil
        lifecycleMessage = nil
        lastTurnText = ""
        store.requestVoiceBootstrap()
        handleVoiceRequestState(store.voiceRequestState)
    }

    private func handleVoiceRequestState(_ state: WatchVoiceRequestState) {
        switch state {
        case .idle, .requesting:
            break
        case let .failed(failure):
            requestFailure = failure
#if os(watchOS)
            WKInterfaceDevice.current().play(.failure)
#endif
        case let .ready(bootstrap):
            guard let usable = store.consumeVoiceBootstrap(requestID: bootstrap.requestID) else { return }
            requestFailure = nil
            Task {
                await realtime.connect(
                    credential: RealtimeClientCredential(
                        value: usable.clientSecretValue,
                        expiresAt: usable.expiresAt
                    ),
                    model: usable.model,
                    instructions: ""
                )
            }
        }
    }

    private func endConversation(forLifecycle: Bool) {
        let wasActive = realtime.isActive || store.voiceRequestState.requestID != nil
        realtime.disconnect()
        store.resetVoiceRequest()
        guard wasActive else { return }
        if forLifecycle {
            lifecycleMessage = "Voice ended when Orbit left the foreground."
        }
#if os(watchOS)
        WKInterfaceDevice.current().play(.stop)
#endif
    }
}

private struct WatchTaskRow: View {
    @EnvironmentObject private var store: WatchTaskStore
    let task: WatchTaskSnapshotItem

    var body: some View {
        HStack(spacing: 7) {
            Button {
                store.complete(task)
            } label: {
                Image(systemName: "circle")
                    .font(.headline)
                    .foregroundStyle(task.priority == .high ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            NavigationLink {
                WatchTaskDetailView(task: task)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if let detail = task.dueDetail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue() ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WatchTaskDetailView: View {
    @EnvironmentObject private var store: WatchTaskStore
    @Environment(\.dismiss) private var dismiss
    let task: WatchTaskSnapshotItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.headline)

                if let detail = task.dueDetail {
                    Label(detail, systemImage: task.isOverdue() ? "exclamationmark.circle.fill" : "calendar")
                        .font(.footnote)
                        .foregroundStyle(task.isOverdue() ? Color.red : Color.secondary)
                }

                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.complete(task)
                    dismiss()
                } label: {
                    Label("Mark complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("To Do")
    }
}

private extension WatchTaskSnapshotItem {
    var dueDetail: String? {
        guard let dueDate else { return nil }
        if isOverdue() { return "Overdue · \(dueDate.formatted(date: .abbreviated, time: .shortened))" }
        if isDueToday() { return "Today · \(dueDate.formatted(date: .omitted, time: .shortened))" }
        return dueDate.formatted(date: .abbreviated, time: .shortened)
    }
}

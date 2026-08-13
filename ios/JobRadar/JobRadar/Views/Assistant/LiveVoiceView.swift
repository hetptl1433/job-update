import SwiftData
import SwiftUI

private extension RealtimeTurnRole {
    var chatRole: ChatMessage.Role {
        switch self {
        case .user: .user
        case .assistant: .assistant
        }
    }
}

/// A focused, full-duplex conversation surface. Live voice and typed chat use
/// one persisted thread, while the Realtime session owns the transient audio
/// state and is torn down whenever this screen leaves the foreground.
struct LiveVoiceView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: EmailRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @StateObject private var realtime = OpenAIRealtimeSession()
    @State private var messages: [ChatMessage] = []
    @State private var didRestoreConversation = false
    @State private var isMintingCredential = false
    @State private var credentialError: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var showConnect = false
    @AppStorage("orbit.ai.financeContextEnabled") private var shareFinanceWithAssistant = false
    @AppStorage("orbit.voice.captionsEnabled") private var captionsEnabled = true

    private var hasAIConnection: Bool {
        app.connections.aiConnected
            && !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    private var phase: LiveVoicePhase {
        if let credentialError { return .failed(credentialError) }
        if isMintingCredential { return .connecting }
        return realtime.phase
    }

    var body: some View {
        ZStack {
            LiveVoiceBackdrop(phase: phase)

            if hasAIConnection {
                conversationSurface
            } else {
                connectionRequiredSurface
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConnect) {
            ConnectChatGPTView()
                .environmentObject(app)
        }
        .onChange(of: realtime.completedTurn) { _, turn in
            guard let turn else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                messages.append(ChatMessage(role: turn.role.chatRole, text: turn.text))
            }
        }
        .onChange(of: messages) { _, messages in
            guard didRestoreConversation else { return }
            AssistantConversationStore.save(messages)
        }
        .onChange(of: app.connections.aiConnected) { _, connected in
            if connected {
                showConnect = false
                startLiveConversation()
            } else {
                stopLiveConversation()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            stopLiveConversation()
        }
        .task {
            if !didRestoreConversation {
                messages = AssistantConversationStore.load()
                didRestoreConversation = true
            }
            if hasAIConnection { startLiveConversation() }
        }
        .onDisappear {
            stopLiveConversation()
        }
    }

    private var conversationSurface: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 12)

            VStack(spacing: 28) {
                OrbitVoiceOrb(
                    phase: phase,
                    inputLevel: realtime.inputAudioLevel,
                    outputLevel: realtime.outputAudioLevel
                )

                VStack(spacing: 7) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)

                    if phase == .connecting {
                        ProgressView()
                            .tint(.white.opacity(0.85))
                            .padding(.top, 4)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: phase)
            }

            Spacer(minLength: 18)

            if captionsEnabled {
                LiveCaptionsView(
                    messages: messages,
                    liveUserText: realtime.liveUserText,
                    liveAssistantText: realtime.liveAssistantText
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Talk naturally — you can interrupt Orbit at any time.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(height: 54)
            }

            controls
                .padding(.top, 18)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: captionsEnabled)
    }

    private var connectionRequiredSurface: some View {
        VStack(spacing: 0) {
            header
            Spacer()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 132, height: 132)
                    Circle()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 132, height: 132)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 9) {
                    Text("Connect ChatGPT for live voice")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Orbit needs your OpenAI connection to start a secure, live conversation. Your saved key is exchanged for a short-lived voice credential.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }

                Button {
                    showConnect = true
                } label: {
                    Label("Connect ChatGPT", systemImage: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 330)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Not now") { endAndDismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 28)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { endAndDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.09), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close live voice")

            VStack(alignment: .leading, spacing: 2) {
                Text("Orbit Voice")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Live conversation")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? Color.green : Color.white.opacity(0.3))
                    .frame(width: 7, height: 7)
                Text(isLive ? "LIVE" : "VOICE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.07), in: Capsule())
        }
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 24) {
            LiveVoiceControl(
                title: realtime.isMuted ? "Unmute" : "Mute",
                systemImage: realtime.isMuted ? "mic.slash.fill" : "mic.fill",
                isSelected: realtime.isMuted,
                isEnabled: realtime.isActive
            ) {
                realtime.toggleMute()
            }

            LiveVoiceControl(
                title: "Captions",
                systemImage: captionsEnabled ? "captions.bubble.fill" : "captions.bubble",
                isSelected: captionsEnabled
            ) {
                captionsEnabled.toggle()
            }

            if canRetry {
                LiveVoiceControl(
                    title: "Retry",
                    systemImage: "arrow.clockwise"
                ) {
                    startLiveConversation()
                }
                .transition(.scale.combined(with: .opacity))
            }

            LiveVoiceControl(
                title: "End",
                systemImage: "phone.down.fill",
                role: .end
            ) {
                endAndDismiss()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canRetry)
    }

    private var isLive: Bool {
        switch phase {
        case .listening, .hearing, .thinking, .speaking, .muted: true
        case .idle, .connecting, .failed: false
        }
    }

    private var canRetry: Bool {
        switch phase {
        case .idle, .failed: true
        default: false
        }
    }

    private var statusTitle: String {
        switch phase {
        case .idle: "Voice is paused"
        case .connecting: "Joining live voice…"
        case .listening: "I'm listening"
        case .hearing: "I hear you"
        case .thinking: "Thinking…"
        case .speaking: "Orbit is speaking"
        case .muted: "Microphone muted"
        case .failed: "Couldn't start voice"
        }
    }

    private var statusDetail: String {
        switch phase {
        case .idle:
            "Tap Retry whenever you're ready to continue."
        case .connecting:
            "Preparing a private snapshot of your Orbit context."
        case .listening:
            "Go ahead — just start talking."
        case .hearing:
            realtime.liveUserText.isEmpty ? "Keep going…" : realtime.liveUserText
        case .thinking:
            "One moment while I work that through."
        case .speaking:
            realtime.liveAssistantText.isEmpty ? "You can interrupt at any time." : realtime.liveAssistantText
        case .muted:
            "Tap Unmute when you want Orbit to hear you again."
        case let .failed(message):
            message
        }
    }

    private var contextBuilder: AssistantContextBuilder {
        AssistantContextBuilder(
            app: app,
            inbox: inbox,
            jobs: jobs,
            shareFinance: shareFinanceWithAssistant
        )
    }

    private func startLiveConversation() {
        guard !isMintingCredential, !realtime.isActive else { return }
        guard let key = KeychainStore.get(KeychainKeys.openAIKey), !key.isEmpty else {
            credentialError = nil
            showConnect = true
            return
        }

        connectionTask?.cancel()
        credentialError = nil
        isMintingCredential = true
        let instructions = AssistantPrompt.realtimeInstructions(
            context: contextBuilder.liveContext(),
            history: messages
        )

        connectionTask = Task { @MainActor in
            defer { isMintingCredential = false }
            do {
                let credential = try await RealtimeClientSecretProvider(apiKey: key)
                    .mintCredential(
                        model: AppConfig.openAIRealtimeModel,
                        instructions: instructions
                    )
                guard !Task.isCancelled else { return }
                await realtime.connect(
                    credential: credential,
                    model: AppConfig.openAIRealtimeModel,
                    instructions: ""
                )
            } catch {
                guard !Task.isCancelled else { return }
                credentialError = error.localizedDescription
            }
        }
    }

    private func stopLiveConversation() {
        connectionTask?.cancel()
        connectionTask = nil
        isMintingCredential = false
        realtime.disconnect()
    }

    private func endAndDismiss() {
        stopLiveConversation()
        app.assistantLaunch = nil
        dismiss()
    }
}

private struct LiveVoiceBackdrop: View {
    let phase: LiveVoicePhase

    private var glow: Color {
        switch phase {
        case .speaking: Color(hex: 0x7769FF)
        case .hearing: Color(hex: 0x37B8A7)
        case .failed: Color(hex: 0xD65364)
        case .muted: Color(hex: 0x6B7180)
        default: Color(hex: 0x4265D6)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x080A0F).ignoresSafeArea()

            Circle()
                .fill(glow.opacity(0.2))
                .frame(width: 460, height: 460)
                .blur(radius: 100)
                .offset(x: -170, y: -310)

            Circle()
                .fill(Color(hex: 0x7156C8).opacity(0.13))
                .frame(width: 390, height: 390)
                .blur(radius: 110)
                .offset(x: 180, y: 340)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.55), value: phase)
    }
}

private struct OrbitVoiceOrb: View {
    let phase: LiveVoicePhase
    let inputLevel: Float
    let outputLevel: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var level: CGFloat {
        let raw = phase == .speaking ? outputLevel : inputLevel
        return CGFloat(max(0, min(raw, 1)))
    }

    private var colors: [Color] {
        switch phase {
        case .hearing:
            [Color(hex: 0x84F1DF), Color(hex: 0x2C9C92), Color(hex: 0x193756)]
        case .speaking:
            [Color(hex: 0xD5B8FF), Color(hex: 0x7669FF), Color(hex: 0x2B326B)]
        case .failed:
            [Color(hex: 0xF0969F), Color(hex: 0xA5364A), Color(hex: 0x421B29)]
        case .muted:
            [Color(hex: 0xBFC3CB), Color(hex: 0x5C6471), Color(hex: 0x282D36)]
        default:
            [Color(hex: 0xA9C9FF), Color(hex: 0x5F7DFF), Color(hex: 0x243C70)]
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(colors[1].opacity(0.16))
                .frame(width: 252, height: 252)
                .blur(radius: 28)
                .scaleEffect((animating && isAnimatedPhase ? 1.08 : 0.94) + level * 0.1)

            Circle()
                .stroke(colors[0].opacity(0.18), lineWidth: 1)
                .frame(width: 222, height: 222)
                .scaleEffect(1 + level * 0.14)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[0], colors[1], colors[2]],
                        center: .topLeading,
                        startRadius: 5,
                        endRadius: 145
                    )
                )
                .frame(width: 188, height: 188)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.36), .clear, .black.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .trim(from: 0.08, to: 0.72)
                        .stroke(
                            AngularGradient(colors: [.clear, .white.opacity(0.62), .clear], center: .center),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .padding(11)
                        .rotationEffect(.degrees(animating && !reduceMotion ? 360 : 0))
                }
                .shadow(color: colors[1].opacity(0.48), radius: 38, y: 14)
                .scaleEffect(1 + level * 0.11)

            Image(systemName: orbSymbol)
                .font(.system(size: 38, weight: .medium))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isAnimatedPhase)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: 270, height: 270)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.72), value: level)
        .animation(.easeInOut(duration: 0.45), value: phase)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit voice activity")
    }

    private var isAnimatedPhase: Bool {
        switch phase {
        case .connecting, .listening, .hearing, .thinking, .speaking: true
        case .idle, .muted, .failed: false
        }
    }

    private var orbSymbol: String {
        switch phase {
        case .connecting: "ellipsis"
        case .muted: "mic.slash.fill"
        case .failed: "exclamationmark"
        default: "waveform"
        }
    }
}

private struct LiveCaptionsView: View {
    let messages: [ChatMessage]
    let liveUserText: String
    let liveAssistantText: String

    private var recentMessages: [ChatMessage] {
        Array(messages.suffix(liveUserText.isEmpty && liveAssistantText.isEmpty ? 2 : 1))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if recentMessages.isEmpty, liveUserText.isEmpty, liveAssistantText.isEmpty {
                        Text("Captions will appear here when the conversation begins.")
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    } else {
                        ForEach(recentMessages) { message in
                            captionLine(role: message.role, text: message.text)
                        }
                        if !liveUserText.isEmpty {
                            captionLine(role: .user, text: liveUserText)
                        }
                        if !liveAssistantText.isEmpty {
                            captionLine(role: .assistant, text: liveAssistantText)
                        }
                    }
                    Color.clear.frame(height: 1).id("caption-bottom")
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: liveUserText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: liveAssistantText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 138)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live captions")
    }

    private func captionLine(role: ChatMessage.Role, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(role == .user ? "YOU" : "ORBIT")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(role == .user ? Color(hex: 0x91C9FF) : Color(hex: 0xC6B5FF))
                .frame(width: 42, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .id("caption-\(role.rawValue)-\(text)")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo("caption-bottom", anchor: .bottom)
        }
    }
}

private struct LiveVoiceControl: View {
    enum Role { case standard, end }

    let title: String
    let systemImage: String
    var isSelected = false
    var isEnabled = true
    var role: Role = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 54, height: 54)
                    .background(background, in: Circle())
                    .overlay(Circle().strokeBorder(border, lineWidth: 1))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.66 : 0.28))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        guard isEnabled else { return .white.opacity(0.24) }
        return role == .end || isSelected ? .white : .white.opacity(0.88)
    }

    private var background: Color {
        if role == .end { return Color(hex: 0xD84756) }
        if isSelected { return .white.opacity(0.2) }
        return .white.opacity(isEnabled ? 0.09 : 0.04)
    }

    private var border: Color {
        role == .end ? .clear : .white.opacity(isSelected ? 0.24 : 0.1)
    }
}

#Preview {
    LiveVoiceView()
        .environmentObject(PreviewSupport.appState())
        .environmentObject(PreviewSupport.appState().inbox)
        .modelContainer(PreviewSupport.container)
}

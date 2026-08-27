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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: [SortDescriptor(\JobApplication.updatedAt, order: .reverse)])
    private var jobs: [JobApplication]

    @StateObject private var realtime = OpenAIRealtimeSession()
    @State private var messages: [ChatMessage] = []
    @State private var didRestoreConversation = false
    @State private var isMintingCredential = false
    @State private var credentialError: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var modelRestartTask: Task<Void, Never>?
    @State private var showConnect = false
    @AppStorage("orbit.ai.financeContextEnabled") private var shareFinanceWithAssistant = false
    @AppStorage("orbit.voice.captionsEnabled") private var captionsEnabled = true
    @AppStorage(AppConfig.openAIRealtimeModelPreferenceKey)
    private var selectedRealtimeModel = AppConfig.bundledOpenAIRealtimeModel

    private var hasAIConnection: Bool {
        app.connections.aiConnected
            && !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    private var phase: LiveVoicePhase {
        if let credentialError { return .failed(credentialError) }
        if isMintingCredential { return .connecting }
        return realtime.phase
    }

    private var selectedRealtimeModelChoice: AIModelChoice {
        AppConfig.realtimeModelChoices(including: selectedRealtimeModel)
            .first { $0.id == selectedRealtimeModel }
            ?? AIModelChoice(
                id: selectedRealtimeModel,
                name: selectedRealtimeModel,
                detail: selectedRealtimeModel
            )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = LiveVoiceLayoutMetrics(
                size: proxy.size,
                dynamicTypeSize: dynamicTypeSize
            )

            ZStack {
                LiveVoiceBackdrop(phase: phase)

                if hasAIConnection {
                    conversationSurface(layout: layout)
                } else {
                    connectionRequiredSurface(layout: layout)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
            if selectedRealtimeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedRealtimeModel = AppConfig.bundledOpenAIRealtimeModel
            }
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

    private func conversationSurface(layout: LiveVoiceLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            header

            if layout.isLandscape {
                landscapeConversationBody(layout: layout)
            } else {
                portraitConversationBody(layout: layout)
            }

            controls(layout: layout)
                .padding(.top, layout.controlsTopPadding)
                .padding(.bottom, layout.controlsBottomPadding)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: captionsEnabled)
    }

    @ViewBuilder
    private func portraitConversationBody(layout: LiveVoiceLayoutMetrics) -> some View {
        if layout.requiresBodyScroll {
            ScrollView {
                portraitConversationContent(layout: layout)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            portraitConversationContent(layout: layout)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func portraitConversationContent(layout: LiveVoiceLayoutMetrics) -> some View {
        VStack(spacing: layout.sectionSpacing) {
            voiceOrb(layout: layout)
            statusBlock(layout: layout)
            captionsBlock(layout: layout)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, layout.bodyTopPadding)
        .padding(.bottom, layout.bodyBottomPadding)
    }

    private func landscapeConversationBody(layout: LiveVoiceLayoutMetrics) -> some View {
        ScrollView {
            HStack(alignment: .center, spacing: layout.sectionSpacing) {
                voiceOrb(layout: layout)

                VStack(spacing: layout.sectionSpacing) {
                    statusBlock(layout: layout)
                    captionsBlock(layout: layout)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, layout.bodyTopPadding)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func voiceOrb(layout: LiveVoiceLayoutMetrics) -> some View {
        OrbitVoiceOrb(
            phase: phase,
            inputLevel: realtime.inputAudioLevel,
            outputLevel: realtime.outputAudioLevel,
            diameter: layout.orbDiameter
        )
    }

    private func statusBlock(layout: LiveVoiceLayoutMetrics) -> some View {
        VStack(spacing: layout.statusSpacing) {
            Text(statusTitle)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())

            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(layout.statusLineLimit)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .frame(maxWidth: layout.statusMaxWidth)

            if phase == .connecting {
                ProgressView()
                    .tint(.white.opacity(0.85))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    @ViewBuilder
    private func captionsBlock(layout: LiveVoiceLayoutMetrics) -> some View {
        if captionsEnabled {
            LiveCaptionsView(
                messages: messages,
                liveUserText: realtime.liveUserText,
                liveAssistantText: realtime.liveAssistantText,
                height: layout.captionHeight,
                isScrollEnabled: !layout.requiresBodyScroll
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text("Talk naturally — you can interrupt Orbit at any time.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.44))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: layout.captionHeight)
        }
    }

    private func connectionRequiredSurface(layout: LiveVoiceLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: layout.connectionSpacing) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.07))
                            .frame(
                                width: layout.connectionIconDiameter,
                                height: layout.connectionIconDiameter
                            )
                        Circle()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            .frame(
                                width: layout.connectionIconDiameter,
                                height: layout.connectionIconDiameter
                            )
                        Image(systemName: "waveform.and.mic")
                            .font(.system(
                                size: layout.connectionIconDiameter * 0.32,
                                weight: .medium
                            ))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 9) {
                        Text("Connect ChatGPT for live voice")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
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
                .frame(
                    maxWidth: .infinity,
                    minHeight: layout.connectionContentMinHeight
                )
                .padding(.vertical, layout.bodyTopPadding)
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Button("Not now") { endAndDismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.vertical, 12)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    private var header: some View {
        ZStack {
            modelMenu

            HStack {
                Spacer()

                Button { endAndDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close live voice")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var modelMenu: some View {
        Menu {
            Section("Live voice model") {
                ForEach(AppConfig.realtimeModelChoices(including: selectedRealtimeModel)) { choice in
                    Button {
                        selectRealtimeModel(choice.id)
                    } label: {
                        Label {
                            Text(choice.name + (choice.isRecommended ? " · Recommended" : ""))
                        } icon: {
                            Image(systemName: choice.id == selectedRealtimeModel ? "checkmark" : "circle")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isLive ? Color(hex: 0x78C99A) : Color.white.opacity(0.28))
                    .frame(width: 6, height: 6)

                Text("VOICE MODEL: \(selectedRealtimeModelChoice.name.uppercased())")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .frame(maxWidth: 236)
            .background(.white.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Voice model, \(selectedRealtimeModelChoice.name)")
        .accessibilityHint("Double tap to choose a different live voice model")
    }

    private func controls(layout: LiveVoiceLayoutMetrics) -> some View {
        HStack(spacing: layout.controlSpacing) {
            LiveVoiceControl(
                title: realtime.isMuted ? "Unmute" : "Mute",
                systemImage: realtime.isMuted ? "mic.slash.fill" : "mic.fill",
                isSelected: realtime.isMuted,
                isEnabled: realtime.isActive,
                role: .microphone,
                diameter: layout.controlDiameter
            ) {
                realtime.toggleMute()
            }

            LiveVoiceControl(
                title: "Captions",
                systemImage: captionsEnabled ? "captions.bubble.fill" : "captions.bubble",
                isSelected: captionsEnabled,
                diameter: layout.controlDiameter
            ) {
                captionsEnabled.toggle()
            }

            if canRetry {
                LiveVoiceControl(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    diameter: layout.controlDiameter
                ) {
                    startLiveConversation()
                }
                .transition(.scale.combined(with: .opacity))
            }

            LiveVoiceControl(
                title: "End",
                systemImage: "phone.down.fill",
                role: .end,
                diameter: layout.controlDiameter
            ) {
                endAndDismiss()
            }
        }
        .padding(8)
        .frame(maxWidth: min(390, layout.size.width - (layout.horizontalPadding * 2)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
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
            realtime.liveUserText.isEmpty ? "Keep going…" : "Listening to you…"
        case .thinking:
            "One moment while I work that through."
        case .speaking:
            "You can interrupt at any time."
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

    private func selectRealtimeModel(_ model: String) {
        guard model != selectedRealtimeModel else { return }
        selectedRealtimeModel = model

        guard hasAIConnection else { return }
        stopLiveConversation()
        modelRestartTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            startLiveConversation()
        }
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
        let model = selectedRealtimeModel

        connectionTask = Task { @MainActor in
            defer { isMintingCredential = false }
            do {
                let credential = try await RealtimeClientSecretProvider(apiKey: key)
                    .mintCredential(
                        model: model,
                        instructions: instructions
                    )
                guard !Task.isCancelled else { return }
                await realtime.connect(
                    credential: credential,
                    model: model,
                    instructions: ""
                )
            } catch {
                guard !Task.isCancelled else { return }
                credentialError = error.localizedDescription
            }
        }
    }

    private func stopLiveConversation() {
        modelRestartTask?.cancel()
        modelRestartTask = nil
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
        GeometryReader { proxy in
            ZStack {
                Color(hex: 0x050607)

                Circle()
                    .fill(glow.opacity(0.1))
                    .frame(width: 440, height: 440)
                    .blur(radius: 130)
                    .offset(x: -150, y: -250)

                Circle()
                    .fill(Color(hex: 0x73839D).opacity(0.07))
                    .frame(width: 360, height: 360)
                    .blur(radius: 130)
                    .offset(x: 170, y: 280)

                LinearGradient(
                    colors: [Color.white.opacity(0.018), .clear, Color.black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.55), value: phase)
    }
}

/// Derives every large visual measurement from the presented safe-area size.
/// An iPhone 15 receives a smaller hero than a Pro Max, while short screens,
/// landscape, and accessibility text keep the header and call controls pinned.
private struct LiveVoiceLayoutMetrics {
    let size: CGSize
    let dynamicTypeSize: DynamicTypeSize

    var isLandscape: Bool { size.width > size.height }
    private var isShort: Bool { size.height < 780 }
    private var usesAccessibilityText: Bool { dynamicTypeSize.isAccessibilitySize }

    var horizontalPadding: CGFloat {
        size.width < 380 ? 14 : 20
    }

    var orbDiameter: CGFloat {
        if isLandscape {
            let proposed = min(size.width * 0.22, size.height * 0.36)
            return min(150, max(116, proposed))
        }

        let heightRatio: CGFloat = isShort ? 0.28 : 0.31
        let accessibilityScale: CGFloat = usesAccessibilityText ? 0.78 : 1
        let proposed = min(size.width * 0.68, size.height * heightRatio, 252)
        return max(168, proposed * accessibilityScale)
    }

    var captionHeight: CGFloat {
        if isLandscape { return min(92, max(70, size.height * 0.22)) }
        if usesAccessibilityText { return min(118, max(92, size.height * 0.14)) }
        return min(112, max(86, size.height * 0.135))
    }

    var statusMaxWidth: CGFloat {
        isLandscape ? min(360, size.width * 0.48) : min(320, size.width - 48)
    }

    var statusLineLimit: Int { usesAccessibilityText ? 4 : 3 }
    var requiresBodyScroll: Bool { isLandscape || usesAccessibilityText || size.height < 700 }
    var statusSpacing: CGFloat { isShort || isLandscape ? 5 : 7 }
    var sectionSpacing: CGFloat { isLandscape ? 14 : (isShort ? 10 : 16) }
    var bodyTopPadding: CGFloat { isLandscape ? 4 : (isShort ? 6 : 12) }
    var bodyBottomPadding: CGFloat { isLandscape ? 4 : (isShort ? 8 : 12) }
    var controlsTopPadding: CGFloat { isLandscape || isShort ? 6 : 10 }
    var controlsBottomPadding: CGFloat { isLandscape ? 2 : 10 }
    var controlSpacing: CGFloat { size.width < 380 ? 2 : 4 }
    var controlDiameter: CGFloat { isLandscape || isShort ? 40 : 44 }
    var connectionSpacing: CGFloat { isLandscape || isShort ? 14 : 22 }

    var connectionIconDiameter: CGFloat {
        if isLandscape { return min(96, max(72, size.height * 0.24)) }
        return min(124, max(94, size.height * 0.15))
    }

    var connectionContentMinHeight: CGFloat {
        max(0, size.height - (isLandscape ? 112 : 132))
    }
}

private struct OrbitVoiceOrb: View {
    let phase: LiveVoicePhase
    let inputLevel: Float
    let outputLevel: Float
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var level: CGFloat {
        let raw = phase == .speaking ? outputLevel : inputLevel
        return CGFloat(max(0, min(raw, 1)))
    }

    private var colors: [Color] {
        switch phase {
        case .hearing:
            [Color(hex: 0xB4D8D0), Color(hex: 0x729B96), Color(hex: 0x40575E)]
        case .speaking:
            [Color(hex: 0xCAC5DD), Color(hex: 0x8C88A7), Color(hex: 0x4D526C)]
        case .failed:
            [Color(hex: 0xD6AFB3), Color(hex: 0x96646C), Color(hex: 0x593D49)]
        case .muted:
            [Color(hex: 0xB7BBC2), Color(hex: 0x737985), Color(hex: 0x414650)]
        default:
            [Color(hex: 0xC0CCDC), Color(hex: 0x8393AA), Color(hex: 0x46546A)]
        }
    }

    var body: some View {
        let scale = diameter / 270
        let activityScale = 1 + level * 0.1
        let isMoving = animating && isAnimatedPhase && !reduceMotion

        ZStack {
            Circle()
                .fill(colors[1].opacity(0.14))
                .frame(width: diameter * 0.86, height: diameter * 0.86)
                .blur(radius: 34 * scale)
                .scaleEffect((isMoving ? 1.06 : 0.96) + level * 0.08)

            RoundedRectangle(cornerRadius: diameter * 0.24, style: .continuous)
                .fill(colors[2].opacity(0.72))
                .frame(width: diameter * 0.67, height: diameter * 0.62)
                .rotationEffect(.degrees(isMoving ? -17 : -8))
                .offset(x: isMoving ? -4 : 2, y: 3)
                .scaleEffect(activityScale)

            RoundedRectangle(cornerRadius: diameter * 0.25, style: .continuous)
                .fill(colors[1].opacity(0.78))
                .frame(width: diameter * 0.64, height: diameter * 0.69)
                .rotationEffect(.degrees(isMoving ? 17 : 9))
                .offset(x: isMoving ? 5 : -2, y: -2)
                .scaleEffect(1 + level * 0.08)

            RoundedRectangle(cornerRadius: diameter * 0.235, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [colors[0], colors[1], colors[2]],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter * 0.64, height: diameter * 0.64)
                .rotationEffect(.degrees(isMoving ? 7 : 3))
                .overlay {
                    RoundedRectangle(cornerRadius: diameter * 0.235, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear, .black.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(
                    color: colors[1].opacity(0.32),
                    radius: 34 * scale,
                    y: 12 * scale
                )
                .scaleEffect(activityScale)

            if let orbSymbol {
                Image(systemName: orbSymbol)
                    .font(.system(size: max(20, 30 * scale), weight: .medium))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isAnimatedPhase)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.72), value: level)
        .animation(.easeInOut(duration: 0.45), value: phase)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
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

    private var orbSymbol: String? {
        switch phase {
        case .connecting: "ellipsis"
        case .muted: "mic.slash.fill"
        case .failed: "exclamationmark"
        default: nil
        }
    }
}

private struct LiveCaptionsView: View {
    let messages: [ChatMessage]
    let liveUserText: String
    let liveAssistantText: String
    let height: CGFloat
    let isScrollEnabled: Bool

    private var recentMessages: [ChatMessage] {
        Array(messages.suffix(liveUserText.isEmpty && liveAssistantText.isEmpty ? 2 : 1))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if recentMessages.isEmpty, liveUserText.isEmpty, liveAssistantText.isEmpty {
                        Text("Captions will appear here when the conversation begins.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.36))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: liveUserText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: liveAssistantText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .scrollDisabled(!isScrollEnabled)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live captions")
    }

    private func captionLine(role: ChatMessage.Role, text: String) -> some View {
        VStack(spacing: 4) {
            Text(role == .user ? "YOU" : "ORBIT")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .id("caption-\(role.rawValue)-\(text)")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo("caption-bottom", anchor: .bottom)
        }
    }
}

private struct LiveVoiceControl: View {
    enum Role { case standard, microphone, end }

    let title: String
    let systemImage: String
    var isSelected = false
    var isEnabled = true
    var role: Role = .standard
    var diameter: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: diameter, height: diameter)
                    .background(background, in: Circle())
                    .overlay(Circle().strokeBorder(border, lineWidth: 1))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.5 : 0.22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .frame(maxWidth: .infinity)
    }

    private var foreground: Color {
        guard isEnabled else { return .white.opacity(0.24) }
        if role == .end { return Color(hex: 0xF0787D) }
        if role == .microphone, !isSelected { return Color(hex: 0x86D69E) }
        return isSelected ? .white : .white.opacity(0.8)
    }

    private var background: Color {
        if role == .end { return Color(hex: 0xD84756).opacity(0.13) }
        if role == .microphone, !isSelected, isEnabled {
            return Color(hex: 0x74D08F).opacity(0.14)
        }
        if isSelected { return .white.opacity(0.2) }
        return .white.opacity(isEnabled ? 0.055 : 0.025)
    }

    private var border: Color {
        if role == .end { return Color(hex: 0xF0787D).opacity(0.32) }
        if role == .microphone, !isSelected, isEnabled {
            return Color(hex: 0x86D69E).opacity(0.22)
        }
        return .white.opacity(isSelected ? 0.2 : 0.07)
    }
}

#Preview {
    LiveVoiceView()
        .environmentObject(PreviewSupport.appState())
        .environmentObject(PreviewSupport.appState().inbox)
        .modelContainer(PreviewSupport.container)
}

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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())

            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
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
                    .lineLimit(1)
                Text("Live conversation")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            .layoutPriority(1)

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
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 8)
    }

    private func controls(layout: LiveVoiceLayoutMetrics) -> some View {
        HStack(alignment: .top, spacing: layout.controlSpacing) {
            LiveVoiceControl(
                title: realtime.isMuted ? "Unmute" : "Mute",
                systemImage: realtime.isMuted ? "mic.slash.fill" : "mic.fill",
                isSelected: realtime.isMuted,
                isEnabled: realtime.isActive,
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
        let model = AppConfig.openAIRealtimeModel

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
                Color(hex: 0x080A0F)

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
        size.width < 380 ? 14 : 18
    }

    var orbDiameter: CGFloat {
        if isLandscape {
            let proposed = min(size.width * 0.22, size.height * 0.36)
            return min(150, max(116, proposed))
        }

        let heightRatio: CGFloat = isShort ? 0.25 : 0.275
        let accessibilityScale: CGFloat = usesAccessibilityText ? 0.78 : 1
        let proposed = min(size.width * 0.62, size.height * heightRatio, 238)
        return max(158, proposed * accessibilityScale)
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
    var sectionSpacing: CGFloat { isLandscape ? 14 : (isShort ? 12 : 18) }
    var bodyTopPadding: CGFloat { isLandscape ? 4 : (isShort ? 8 : 14) }
    var bodyBottomPadding: CGFloat { isLandscape ? 4 : (isShort ? 8 : 12) }
    var controlsTopPadding: CGFloat { isLandscape || isShort ? 6 : 10 }
    var controlsBottomPadding: CGFloat { isLandscape ? 2 : 8 }
    var controlSpacing: CGFloat { size.width < 380 ? 2 : 6 }
    var controlDiameter: CGFloat { isLandscape || isShort ? 48 : 52 }
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
        let scale = diameter / 270

        ZStack {
            Circle()
                .fill(colors[1].opacity(0.16))
                .frame(width: diameter * 0.933, height: diameter * 0.933)
                .blur(radius: 28 * scale)
                .scaleEffect((animating && isAnimatedPhase ? 1.08 : 0.94) + level * 0.1)

            Circle()
                .stroke(colors[0].opacity(0.18), lineWidth: 1)
                .frame(width: diameter * 0.822, height: diameter * 0.822)
                .scaleEffect(1 + level * 0.14)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[0], colors[1], colors[2]],
                        center: .topLeading,
                        startRadius: 5 * scale,
                        endRadius: diameter * 0.537
                    )
                )
                .frame(width: diameter * 0.696, height: diameter * 0.696)
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
                        .padding(11 * scale)
                        .rotationEffect(.degrees(animating && !reduceMotion ? 360 : 0))
                }
                .shadow(
                    color: colors[1].opacity(0.48),
                    radius: 38 * scale,
                    y: 14 * scale
                )
                .scaleEffect(1 + level * 0.11)

            Image(systemName: orbSymbol)
                .font(.system(size: max(24, 38 * scale), weight: .medium))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isAnimatedPhase)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: diameter, height: diameter)
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
    let height: CGFloat
    let isScrollEnabled: Bool

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
            .scrollDisabled(!isScrollEnabled)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
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
    var diameter: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: diameter, height: diameter)
                    .background(background, in: Circle())
                    .overlay(Circle().strokeBorder(border, lineWidth: 1))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.66 : 0.28))
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

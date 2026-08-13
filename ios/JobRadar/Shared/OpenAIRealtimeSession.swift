import AVFoundation
import Combine
import Foundation

enum RealtimeTurnRole: String, Codable, Sendable {
    case user
    case assistant
}

enum LiveVoicePhase: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case hearing
    case thinking
    case speaking
    case muted
    case failed(String)
}

struct RealtimeClientCredential: Codable, Equatable, Sendable {
    let value: String
    let expiresAt: Date?

    init(value: String, expiresAt: Date? = nil) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

/// Keeps the client-secret and WebSocket session configuration in lockstep.
/// A model is included while minting a secret, but omitted from a later
/// `session.update` because the WebSocket URL already selects it.
enum RealtimeSessionConfigurationPayload {
    static func make(model: String?, instructions: String) -> [String: Any] {
        var session: [String: Any] = [
            "type": "realtime",
            "instructions": instructions,
            "output_modalities": ["audio"],
            "max_output_tokens": 1_200,
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24_000
                    ],
                    "noise_reduction": ["type": "near_field"],
                    "transcription": [
                        "model": "gpt-4o-mini-transcribe",
                        "prompt": "A personal assistant conversation. Expect Orbit, Gmail, Outlook, recruiter, interview, calendar, finance, and To Do."
                    ],
                    "turn_detection": [
                        "type": "semantic_vad",
                        "eagerness": "medium",
                        "create_response": true,
                        "interrupt_response": true
                    ]
                ],
                "output": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24_000
                    ],
                    "voice": "marin",
                    "speed": 1.0
                ]
            ]
        ]
        if let model, !model.isEmpty { session["model"] = model }
        return session
    }
}

// MARK: - OpenAI Realtime speech-to-speech

/// A continuous OpenAI Realtime conversation. Unlike `VoiceAssistantAudio`,
/// which stitches together speech recognition, a text request, and local TTS,
/// this session streams microphone audio to a Realtime model and plays the
/// model's native audio response while transcript events drive the chat UI.
///
/// Authenticate distributed clients with a short-lived
/// `RealtimeClientCredential`; the long-lived OpenAI key should remain on the
/// credential-issuing device or backend.
@MainActor
final class OpenAIRealtimeSession: ObservableObject {
    enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case connected
    }

    struct CompletedTurn: Identifiable, Equatable {
        let id = UUID()
        let role: RealtimeTurnRole
        let text: String
    }

    @Published private(set) var state: ConnectionState = .idle {
        didSet { updatePhase() }
    }
    @Published private(set) var isMuted = false {
        didSet { updatePhase() }
    }
    @Published private(set) var isUserSpeaking = false {
        didSet { updatePhase() }
    }
    @Published private(set) var isAssistantSpeaking = false {
        didSet { updatePhase() }
    }
    @Published private(set) var isResponding = false {
        didSet { updatePhase() }
    }
    @Published private(set) var liveUserText = ""
    @Published private(set) var liveAssistantText = ""
    @Published private(set) var completedTurn: CompletedTurn?
    @Published private(set) var errorMessage: String? {
        didSet { updatePhase() }
    }
    @Published private(set) var phase: LiveVoicePhase = .idle
    @Published private(set) var inputAudioLevel: Float = 0
    @Published private(set) var outputAudioLevel: Float = 0

    var isActive: Bool { state != .idle }
    var isConnected: Bool { state == .connected }

    private let audioIO = RealtimeAudioIO()
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var connectionAttemptID: UUID?
    private var instructions = ""
    private var pendingInputAudio = Data()
    private var currentUserItemID: String?
    private var currentAssistantItemID: String?
    private var currentResponseID: String?
    private var userTranscript = ""
    private var assistantTranscript = ""
    private var assistantAudioStartedForItem: String?
    private var finalizedUserItems = Set<String>()
    private var finalizedAssistantItems = Set<String>()
    private var awaitingUserTranscript = false
    private var pendingAssistantTurn: CompletedTurn?
    private var outgoingMessages: [String] = []
    private var isSendingEvent = false
    private var didStartAudio = false

    init() {
        audioIO.onInputAudio = { [weak self] data in
            Task { @MainActor in
                self?.queueInputAudio(data)
            }
        }
        audioIO.onInputAudioLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.inputAudioLevel = self.isConnected && !self.isMuted ? level : 0
            }
        }
        audioIO.onOutputAudioLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.outputAudioLevel = self.isConnected ? level : 0
            }
        }
        audioIO.onPlaybackDrained = { [weak self] in
            Task { @MainActor in
                self?.isAssistantSpeaking = false
                self?.outputAudioLevel = 0
            }
        }
    }

    deinit {
        handshakeTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        audioIO.stop()
    }

    /// Compatibility for the owner's BYOK iPhone flow. Production callers
    /// should mint a short-lived credential and call the credential overload.
    func connect(apiKey: String, instructions: String) async {
        await connect(
            credential: RealtimeClientCredential(value: apiKey),
            model: "gpt-realtime-2.1",
            instructions: instructions
        )
    }

    /// Connects with either an ephemeral client secret or another accepted
    /// bearer credential. Pass an empty `instructions` string only when the
    /// client secret was minted with the full session configuration; in that
    /// case no redundant `session.update` event is sent.
    func connect(
        credential: RealtimeClientCredential,
        model: String,
        instructions: String
    ) async {
        disconnect()
        let attemptID = UUID()
        connectionAttemptID = attemptID

        let credentialValue = credential.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credentialValue.isEmpty else {
            fail("A live voice credential is required.")
            return
        }
        if let expiresAt = credential.expiresAt, expiresAt <= Date().addingTimeInterval(3) {
            fail("The live voice credential expired. Start a new conversation to reconnect.")
            return
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            fail("A Realtime model is required to start live voice.")
            return
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard connectionAttemptID == attemptID else { return }
        guard !Task.isCancelled else {
            connectionAttemptID = nil
            return
        }
        guard microphoneGranted else {
            fail("Microphone access is off. Enable it in Settings → Orbit.")
            return
        }

        guard var components = URLComponents(string: "wss://api.openai.com/v1/realtime") else {
            fail("Orbit couldn't create the live conversation connection.")
            return
        }
        components.queryItems = [
            URLQueryItem(name: "model", value: trimmedModel)
        ]
        guard let url = components.url else {
            fail("Orbit couldn't create the live conversation connection.")
            return
        }

        self.instructions = instructions
        state = .connecting

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentialValue)", forHTTPHeaderField: "Authorization")

        let socket = URLSession.shared.webSocketTask(with: request)
        webSocket = socket
        socket.resume()

        receiveTask = Task { [weak self, weak socket] in
            guard let self, let socket else { return }
            await self.receiveMessages(from: socket)
        }
        handshakeTask = Task { [weak self, weak socket] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, let socket,
                  self.webSocket === socket, self.state == .connecting else { return }
            self.fail("Live voice took too long to connect. Check your network and try again.")
        }
    }

    func disconnect() {
        connectionAttemptID = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        let socket = webSocket
        webSocket = nil
        socket?.cancel(with: .goingAway, reason: nil)

        audioIO.stop()
        errorMessage = nil
        state = .idle
        isMuted = false
        isUserSpeaking = false
        isAssistantSpeaking = false
        isResponding = false
        liveUserText = ""
        liveAssistantText = ""
        inputAudioLevel = 0
        outputAudioLevel = 0
        pendingInputAudio.removeAll(keepingCapacity: false)
        currentUserItemID = nil
        currentAssistantItemID = nil
        currentResponseID = nil
        userTranscript = ""
        assistantTranscript = ""
        assistantAudioStartedForItem = nil
        finalizedUserItems.removeAll()
        finalizedAssistantItems.removeAll()
        awaitingUserTranscript = false
        pendingAssistantTurn = nil
        outgoingMessages.removeAll(keepingCapacity: false)
        isSendingEvent = false
        didStartAudio = false
    }

    func toggleMute() {
        guard isActive else { return }
        isMuted.toggle()
        if isMuted {
            pendingInputAudio.removeAll(keepingCapacity: true)
            isUserSpeaking = false
            liveUserText = ""
            userTranscript = ""
            if isConnected {
                sendEvent(["type": "input_audio_buffer.clear"])
            }
        }
    }

    /// Adds a typed message to the same live conversation. The response still
    /// arrives as native model speech plus streaming transcript events.
    func sendText(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !clean.isEmpty else { return }

        if isAssistantSpeaking || isResponding {
            sendEvent(["type": "response.cancel"])
            interruptAssistantIfNeeded()
        }

        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": clean
                ]]
            ]
        ])
        sendEvent(["type": "response.create"])
        isResponding = true
    }

    /// Mirrors a deterministic, app-handled exchange into the live session so
    /// the next spoken turn still has the result in its conversation memory.
    func recordLocalExchange(userText: String, assistantText: String) {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !user.isEmpty, !assistant.isEmpty else { return }

        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": user]]
            ]
        ])
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "assistant",
                "content": [["type": "output_text", "text": assistant]]
            ]
        ])
    }

    private func receiveMessages(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard webSocket === socket else { return }

                switch message {
                case let .string(text):
                    handleServerMessage(Data(text.utf8))
                case let .data(data):
                    handleServerMessage(data)
                @unknown default:
                    break
                }
            } catch {
                guard webSocket === socket, !Task.isCancelled else { return }
                fail("Live voice disconnected: \(error.localizedDescription)")
                return
            }
        }
    }

    private func handleServerMessage(_ data: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created":
            if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startAudioIfNeeded()
            } else {
                sendSessionConfiguration()
            }

        case "session.updated":
            startAudioIfNeeded()

        case "input_audio_buffer.speech_started":
            currentUserItemID = event["item_id"] as? String ?? currentUserItemID
            userTranscript = ""
            liveUserText = ""
            isUserSpeaking = true
            isResponding = false
            awaitingUserTranscript = true
            interruptAssistantIfNeeded()

        case "input_audio_buffer.speech_stopped":
            isUserSpeaking = false
            isResponding = true

        case "input_audio_buffer.committed":
            currentUserItemID = event["item_id"] as? String ?? currentUserItemID

        case "conversation.item.input_audio_transcription.delta":
            beginUserTranscriptIfNeeded(itemID: event["item_id"] as? String)
            appendTranscriptDelta(event["delta"] as? String, toUser: true)

        case "conversation.item.input_audio_transcription.completed":
            beginUserTranscriptIfNeeded(itemID: event["item_id"] as? String)
            let final = (event["transcript"] as? String) ?? userTranscript
            finalizeUserTranscript(final, itemID: event["item_id"] as? String)

        case "conversation.item.input_audio_transcription.failed":
            isUserSpeaking = false
            awaitingUserTranscript = false
            errorMessage = nestedMessage(in: event)
                ?? "Orbit heard a turn, but couldn't create its transcript."
            emitPendingAssistantTurn()

        case "response.created":
            currentResponseID = (event["response"] as? [String: Any])?["id"] as? String
            currentAssistantItemID = nil
            assistantAudioStartedForItem = nil
            isResponding = true
            assistantTranscript = ""
            liveAssistantText = ""

        case "response.output_item.added":
            if let item = event["item"] as? [String: Any],
               let itemID = item["id"] as? String {
                currentAssistantItemID = itemID
            }

        case "response.output_audio.delta", "response.audio.delta":
            beginAssistantAudioIfNeeded(itemID: event["item_id"] as? String)
            if let encoded = event["delta"] as? String,
               let audio = Data(base64Encoded: encoded),
               !audio.isEmpty {
                audioIO.scheduleOutput(audio)
                isAssistantSpeaking = true
                isResponding = false
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta",
             "response.output_text.delta", "response.text.delta":
            beginAssistantTranscriptIfNeeded(itemID: event["item_id"] as? String)
            appendTranscriptDelta(event["delta"] as? String, toUser: false)

        case "response.output_audio_transcript.done", "response.audio_transcript.done",
             "response.output_text.done", "response.text.done":
            beginAssistantTranscriptIfNeeded(itemID: event["item_id"] as? String)
            let final = (event["transcript"] as? String)
                ?? (event["text"] as? String)
                ?? assistantTranscript
            finalizeAssistantTranscript(final, itemID: event["item_id"] as? String)

        case "response.done":
            isResponding = false
            if !assistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeAssistantTranscript(assistantTranscript, itemID: currentAssistantItemID)
            }
            if let response = event["response"] as? [String: Any],
               let status = response["status"] as? String,
               status == "failed" {
                errorMessage = nestedMessage(in: response)
                    ?? "The live response couldn't be completed."
            }

        case "response.cancelled":
            isResponding = false

        case "error":
            let message = nestedMessage(in: event) ?? "The Realtime API returned an error."
            if state == .connecting {
                fail(message)
            } else {
                errorMessage = message
            }

        default:
            break
        }
    }

    private func sendSessionConfiguration() {
        sendEvent([
            "type": "session.update",
            "session": RealtimeSessionConfigurationPayload.make(
                model: nil,
                instructions: instructions
            )
        ])
    }

    private func startAudioIfNeeded() {
        guard !didStartAudio else { return }
        do {
            try audioIO.start()
            didStartAudio = true
            handshakeTask?.cancel()
            handshakeTask = nil
            state = .connected
            errorMessage = nil
        } catch {
            fail("Live audio couldn't start: \(error.localizedDescription)")
        }
    }

    private func queueInputAudio(_ data: Data) {
        guard isConnected, !isMuted, !data.isEmpty else { return }
        pendingInputAudio.append(data)

        // Roughly 50 ms of 24 kHz, mono, 16-bit PCM. Small batches keep VAD
        // responsive without creating a WebSocket message for every audio tap.
        guard pendingInputAudio.count >= 2_400 else { return }
        let chunk = pendingInputAudio
        pendingInputAudio.removeAll(keepingCapacity: true)
        sendEvent([
            "type": "input_audio_buffer.append",
            "audio": chunk.base64EncodedString()
        ])
    }

    private func beginUserTranscriptIfNeeded(itemID: String?) {
        guard let itemID, itemID != currentUserItemID else { return }
        currentUserItemID = itemID
        userTranscript = ""
        liveUserText = ""
    }

    private func beginAssistantTranscriptIfNeeded(itemID: String?) {
        if let itemID, itemID != currentAssistantItemID {
            currentAssistantItemID = itemID
            assistantTranscript = ""
            liveAssistantText = ""
        }
    }

    private func beginAssistantAudioIfNeeded(itemID: String?) {
        if let itemID { currentAssistantItemID = itemID }
        let identity = currentAssistantItemID ?? currentResponseID ?? "active-response"
        guard assistantAudioStartedForItem != identity else { return }
        assistantAudioStartedForItem = identity
        audioIO.beginResponse()
    }

    private func appendTranscriptDelta(_ delta: String?, toUser: Bool) {
        guard let delta, !delta.isEmpty else { return }
        if toUser {
            userTranscript += delta
            liveUserText = userTranscript
        } else {
            assistantTranscript += delta
            liveAssistantText = assistantTranscript
        }
    }

    private func finalizeUserTranscript(_ text: String, itemID: String?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let identity = itemID ?? currentUserItemID ?? "user-\(UUID().uuidString)"
        guard finalizedUserItems.insert(identity).inserted else { return }

        userTranscript = clean
        liveUserText = clean
        completedTurn = CompletedTurn(role: .user, text: clean)
        awaitingUserTranscript = false
        userTranscript = ""
        liveUserText = ""
        isUserSpeaking = false
        emitPendingAssistantTurn()
    }

    private func finalizeAssistantTranscript(_ text: String, itemID: String?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let identity = itemID ?? currentAssistantItemID ?? currentResponseID
            ?? "assistant-\(UUID().uuidString)"
        guard finalizedAssistantItems.insert(identity).inserted else { return }

        assistantTranscript = clean
        liveAssistantText = clean
        let turn = CompletedTurn(role: .assistant, text: clean)
        if awaitingUserTranscript {
            pendingAssistantTurn = turn
        } else {
            completedTurn = turn
        }
        assistantTranscript = ""
        liveAssistantText = ""
        isResponding = false
    }

    private func interruptAssistantIfNeeded() {
        guard isAssistantSpeaking else { return }
        let playedMilliseconds = audioIO.interruptOutput()
        isAssistantSpeaking = false

        guard let itemID = currentAssistantItemID, playedMilliseconds > 0 else { return }
        sendEvent([
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": 0,
            "audio_end_ms": playedMilliseconds
        ])
    }

    private func sendEvent(_ event: [String: Any]) {
        guard webSocket != nil, JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }

        outgoingMessages.append(text)
        sendNextEventIfNeeded()
    }

    private func sendNextEventIfNeeded() {
        guard !isSendingEvent,
              let socket = webSocket,
              !outgoingMessages.isEmpty else { return }

        isSendingEvent = true
        let text = outgoingMessages.removeFirst()

        Task { [weak self, weak socket] in
            guard let self, let socket, self.webSocket === socket else { return }
            do {
                try await socket.send(.string(text))
                guard self.webSocket === socket else { return }
                self.isSendingEvent = false
                self.sendNextEventIfNeeded()
            } catch {
                guard self.webSocket === socket else { return }
                self.fail("Live voice couldn't send audio: \(error.localizedDescription)")
            }
        }
    }

    private func emitPendingAssistantTurn() {
        guard let pendingAssistantTurn else { return }
        self.pendingAssistantTurn = nil
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isActive else { return }
            self.completedTurn = pendingAssistantTurn
        }
    }

    private func nestedMessage(in object: [String: Any]) -> String? {
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String { return message }
        if let details = object["status_details"] as? [String: Any] {
            return nestedMessage(in: details)
        }
        return nil
    }

    private func fail(_ message: String) {
        disconnect()
        errorMessage = message
    }

    private func updatePhase() {
        let next: LiveVoicePhase
        if state == .idle, let errorMessage {
            next = .failed(errorMessage)
        } else {
            switch state {
            case .idle:
                next = .idle
            case .connecting:
                next = .connecting
            case .connected where isMuted:
                next = .muted
            case .connected where isAssistantSpeaking:
                next = .speaking
            case .connected where isUserSpeaking:
                next = .hearing
            case .connected where isResponding:
                next = .thinking
            case .connected:
                next = .listening
            }
        }
        if phase != next { phase = next }
    }
}

/// Full-duplex PCM bridge used by `OpenAIRealtimeSession`. AVAudioConverter
/// normalizes the current device microphone format to the Realtime API's required
/// 24 kHz mono PCM16 format; the player node performs the reverse conversion
/// to the device's current output route.
private final class RealtimeAudioIO {
    var onInputAudio: ((Data) -> Void)?
    var onInputAudioLevel: ((Float) -> Void)?
    var onOutputAudioLevel: ((Float) -> Void)?
    var onPlaybackDrained: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private var inputTapInstalled = false
    private var scheduledBufferCount = 0
    private var playbackGeneration = 0
    private var responseStartSampleTime: AVAudioFramePosition?
    private var responseScheduledFrames: AVAudioFramePosition = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
    }

    func start() throws {
        stop()

        let session = AVAudioSession.sharedInstance()
#if os(watchOS)
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.duckOthers]
        )
#else
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )
        try session.setPreferredIOBufferDuration(0.02)
#endif
        try session.setActive(true)

        let inputNode = engine.inputNode
        try? inputNode.setVoiceProcessingEnabled(true)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: wireFormat) else {
            throw RealtimeAudioError.noInput
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self,
                  let data = Self.convertInput(
                    buffer,
                    converter: converter,
                    outputFormat: self.wireFormat
                  ),
                  !data.isEmpty else { return }
            self.onInputAudioLevel?(Self.audioLevel(forPCM16: data))
            self.onInputAudio?(data)
        }
        inputTapInstalled = true

        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        playbackGeneration += 1
        player.stop()
        if engine.isRunning { engine.stop() }
        if inputTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        engine.reset()
        scheduledBufferCount = 0
        responseStartSampleTime = nil
        responseScheduledFrames = 0
        onInputAudioLevel?(0)
        onOutputAudioLevel?(0)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func beginResponse() {
        responseStartSampleTime = currentSampleTime() ?? 0
        responseScheduledFrames = 0
    }

    func scheduleOutput(_ data: Data) {
        guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Int16>.size) else { return }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: frameCount
        ), let destination = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount

        var samples = [Int16](repeating: 0, count: Int(frameCount))
        _ = samples.withUnsafeMutableBytes { bytes in
            data.copyBytes(to: bytes)
        }
        for index in samples.indices {
            destination[index] = Float(Int16(littleEndian: samples[index])) / 32_768
        }
        onOutputAudioLevel?(Self.audioLevel(for: samples))

        let generation = playbackGeneration
        scheduledBufferCount += 1
        responseScheduledFrames += AVAudioFramePosition(frameCount)
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                if self.scheduledBufferCount == 0 {
                    self.onPlaybackDrained?()
                }
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Stops queued model audio and returns the approximate amount already
    /// rendered for the current response, which the caller uses to truncate
    /// the server-side conversation after a user interruption.
    func interruptOutput() -> Int {
        let current = currentSampleTime() ?? responseStartSampleTime ?? 0
        let start = responseStartSampleTime ?? current
        let playedFrames = max(0, min(current - start, responseScheduledFrames))
        let milliseconds = Int((Double(playedFrames) / wireFormat.sampleRate) * 1_000)

        playbackGeneration += 1
        player.stop()
        player.reset()
        scheduledBufferCount = 0
        responseStartSampleTime = nil
        responseScheduledFrames = 0
        onOutputAudioLevel?(0)
        if engine.isRunning { player.play() }
        return milliseconds
    }

    private func currentSampleTime() -> AVAudioFramePosition? {
        guard let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime) else { return nil }
        return playerTime.sampleTime
    }

    private static func convertInput(
        _ input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> Data? {
        let scale = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * scale)) + 16
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else { return nil }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return input
        }
        guard conversionError == nil, output.frameLength > 0 else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard let source = buffers.first?.mData else { return nil }
        let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: source, count: byteCount)
    }

    private static func audioLevel(forPCM16 data: Data) -> Float {
        guard !data.isEmpty else { return 0 }
        var samples = [Int16](repeating: 0, count: data.count / MemoryLayout<Int16>.size)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return audioLevel(for: samples)
    }

    private static func audioLevel(for samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var squareSum = 0.0
        for sample in samples {
            let normalized = Double(Int16(littleEndian: sample)) / 32_768
            squareSum += normalized * normalized
        }
        let rms = sqrt(squareSum / Double(samples.count))
        return Float(min(1, rms * 5))
    }
}

private enum RealtimeAudioError: LocalizedError {
    case noInput

    var errorDescription: String? {
        "No microphone input is available."
    }
}

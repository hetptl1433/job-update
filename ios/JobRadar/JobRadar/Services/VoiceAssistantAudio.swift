import AVFoundation
import Combine
import Foundation
import Speech

/// Owns the short-lived audio session used by Orbit voice mode. Speech is
/// transcribed locally when the current language supports on-device recognition.
@MainActor
final class VoiceAssistantAudio: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isFinal = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var completedSpeechCount = 0
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false
    private var awaitingFinalResult = false
    private var silenceTask: Task<Void, Never>?
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startListening() async {
        stopListening()
        stopSpeaking()
        transcript = ""
        isFinal = false
        errorMessage = nil

        guard await requestPermissions() else { return }
        guard let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent),
              recognizer.isAvailable else {
            errorMessage = "Speech recognition is temporarily unavailable."
            return
        }

        do {
            try activateListeningSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "Orbit", "Gmail", "Outlook", "recruiter", "interview",
                "follow-up", "calendar", "reminder", "To Do"
            ]
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceAudioError.noInput
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            inputTapInstalled = true

            isListening = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finishCapture(cancelRecognition: false)
                            self.isFinal = true
                        } else if !self.transcript.isEmpty {
                            self.scheduleSilenceFinish()
                        }
                    }
                    if let error, self.isListening || self.awaitingFinalResult {
                        self.errorMessage = "I couldn't hear that clearly: \(error.localizedDescription)"
                        self.finishCapture(cancelRecognition: true)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = error.localizedDescription
            finishCapture(cancelRecognition: true)
        }
    }

    func stopListening() {
        finishCapture(cancelRecognition: true)
    }

    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        stopListening()
        activeUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try activateSpeechSession()
            errorMessage = nil
        } catch {
            isSpeaking = false
            errorMessage = "Orbit wrote a reply, but audio playback couldn't start: \(error.localizedDescription)"
            return
        }

        let utterance = AVSpeechUtterance(string: clean)
        let preferredLanguage = Locale.preferredLanguages.first ?? "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: preferredLanguage)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        activeUtteranceID = ObjectIdentifier(utterance)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        activeUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivateAudioSession()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.activeUtteranceID = nil
            self.isSpeaking = false
            self.deactivateAudioSession()
            self.completedSpeechCount += 1
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.activeUtteranceID = nil
            self.isSpeaking = false
            self.deactivateAudioSession()
        }
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            errorMessage = speechStatus == .denied
                ? "Speech recognition is off. Enable it in Settings → Orbit."
                : "Speech recognition isn't available on this iPhone."
            return false
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            errorMessage = "Microphone access is off. Enable it in Settings → Orbit."
            return false
        }
        return true
    }

    private func finishCapture(cancelRecognition: Bool) {
        silenceTask?.cancel()
        silenceTask = nil
        stopEngineAndTap()
        recognitionRequest?.endAudio()
        if cancelRecognition { recognitionTask?.cancel() }
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        awaitingFinalResult = false
        deactivateAudioSession()
    }

    private func scheduleSilenceFinish() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            self?.finishInputGracefully()
        }
    }

    private func finishInputGracefully() {
        guard isListening else { return }
        silenceTask?.cancel()
        silenceTask = nil
        stopEngineAndTap()
        recognitionRequest?.endAudio()
        isListening = false
        awaitingFinalResult = true
        deactivateAudioSession()
    }

    private func stopEngineAndTap() {
        if audioEngine.isRunning { audioEngine.stop() }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        audioEngine.reset()
    }

    private func activateListeningSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true)
    }

    private func activateSpeechSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

private enum VoiceAudioError: LocalizedError {
    case noInput

    var errorDescription: String? {
        "No microphone input is available."
    }
}

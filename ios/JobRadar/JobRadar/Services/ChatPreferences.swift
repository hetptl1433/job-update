import Foundation

/// How long Orbit Chat reasons before it answers. OpenAI models offer every
/// mode; on-device models either answer right away or think first.
enum ChatThinkingMode: String, CaseIterable, Identifiable {
    case instant
    case balanced
    case thinking
    case deep

    static let onDeviceModes: [ChatThinkingMode] = [.instant, .thinking]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instant: "Instant"
        case .balanced: "Balanced"
        case .thinking: "Think"
        case .deep: "Deep"
        }
    }

    var systemImage: String {
        switch self {
        case .instant: "bolt"
        case .balanced: "circle.lefthalf.filled"
        case .thinking: "brain"
        case .deep: "brain.head.profile"
        }
    }

    var openAIDetail: String {
        switch self {
        case .instant: "Answers right away, without reasoning. Fastest and cheapest."
        case .balanced: "Reasons as much as each question needs."
        case .thinking: "Thinks longer for tricky, multi-step questions."
        case .deep: "The most thorough answers. Slower, and uses more of your API budget."
        }
    }

    var reasoningEffort: OpenAIClient.ReasoningEffort {
        switch self {
        case .instant: .off
        case .balanced: .medium
        case .thinking: .high
        case .deep: .xhigh
        }
    }

    /// Reasoning tokens count toward the output limit, so longer thinking
    /// needs more room. Models that don't reason keep the usual limit.
    func maxOutputTokens(reasons: Bool) -> Int {
        guard reasons else { return 4_000 }
        switch self {
        case .instant: return 2_000
        case .balanced: return 4_000
        case .thinking: return 12_000
        case .deep: return 25_000
        }
    }

    var requestTimeout: TimeInterval {
        switch self {
        case .instant: 60
        case .balanced: 90
        case .thinking: 180
        case .deep: 300
        }
    }
}

/// Orbit Chat's saved model and thinking choices. Services read these when
/// they answer, so a change in the chat applies to the next question.
enum ChatPreferences {
    static let openAIThinkingKey = "orbit.ai.chatThinking.openAI"
    static let onDeviceThinkingKey = "orbit.ai.chatThinking.onDevice"

    static func openAIThinking(defaults: UserDefaults = .standard) -> ChatThinkingMode {
        defaults.string(forKey: openAIThinkingKey).flatMap(ChatThinkingMode.init(rawValue:)) ?? .balanced
    }

    static func onDeviceThinking(defaults: UserDefaults = .standard) -> ChatThinkingMode {
        let mode = defaults.string(forKey: onDeviceThinkingKey).flatMap(ChatThinkingMode.init(rawValue:)) ?? .instant
        return ChatThinkingMode.onDeviceModes.contains(mode) ? mode : .instant
    }

    /// The mode a question to `model` actually uses: `nil` when the model
    /// can't reason.
    static func openAIThinking(for model: String, defaults: UserDefaults = .standard) -> ChatThinkingMode? {
        OpenAIClient.reasoningEfforts(forModel: model).isEmpty ? nil : openAIThinking(defaults: defaults)
    }

    static func onDeviceThinking(for option: LocalModelOption?, defaults: UserDefaults = .standard) -> ChatThinkingMode? {
        guard let option, option.supportsThinking else { return nil }
        return onDeviceThinking(defaults: defaults)
    }
}

import Foundation

/// A curated model choice for an Orbit workload. The API model catalog also
/// contains embeddings, image, transcription, and other incompatible models,
/// so Settings intentionally offers only models that fit this app's requests.
struct AIModelChoice: Identifiable, Hashable {
    enum Cost: Int {
        case unknown, low, medium, high

        var title: String? {
            switch self {
            case .unknown: nil
            case .low: "Low cost"
            case .medium: "Medium cost"
            case .high: "Higher cost"
            }
        }
    }

    let id: String
    let name: String
    let detail: String
    var isRecommended = false
    var cost: Cost = .unknown
}

/// Central, non-secret application configuration.
///
/// Nothing sensitive lives here. The OpenAI key never ships in the app — the
/// client only knows how to reach *our* backend, which brokers AI requests.
enum AppConfig {
    static let openAIModelPreferenceKey = "orbit.ai.textModel"
    static let openAIChatModelPreferenceKey = "orbit.ai.chatModel"
    static let openAIRealtimeModelPreferenceKey = "orbit.ai.realtimeModel"
    static let assistantEnginePreferenceKey = "orbit.ai.chatEngine"
    static let localModelPreferenceKey = "orbit.ai.localModel"

    /// User-facing product name. Change in this one place to rebrand.
    static let appName = "Orbit"

    /// Short tagline used on the welcome screen.
    static let tagline = "Your life. One place."

    /// Optional tracker/push backend. There is deliberately no production
    /// fallback: an incorrect URL must never be treated as a working API.
    static var apiBaseURL: URL? {
        configuredURL(forInfoKey: "APIBaseURL")
    }

    /// Finance is deployed independently from the optional tracker/push API.
    /// Keeping these URLs separate prevents a Finance-only server from causing
    /// misleading job refresh failures.
    static var financeAPIBaseURL: URL? {
        configuredURL(forInfoKey: "FinanceAPIBaseURL")
    }

    /// Google OAuth client ID. Supplied by the Google Cloud console and stored
    /// in Info.plist under `GIDClientID`. Empty until the user configures it —
    /// the auth layer surfaces a clear "not configured" error rather than
    /// crashing so the app still builds and runs.
    static var googleClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    static var isGoogleConfigured: Bool { googleClientID != nil }

    /// Microsoft Entra public-client registration. A client ID is intentionally
    /// not invented; Outlook connection remains disabled until the developer
    /// registers bundle ID `com.hetpatel.jobradar` and supplies the value.
    static var microsoftClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "MicrosoftClientID") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    static var microsoftTenantID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "MicrosoftTenantID") as? String
        return value?.isEmpty == false ? value! : "common"
    }

    static var microsoftRedirectURI: String {
        "msauth.\(Bundle.main.bundleIdentifier ?? "com.hetpatel.jobradar")://auth"
    }

    /// Bundled fallback for email extraction and the in-app assistant. Existing
    /// installs keep this behavior until the owner chooses another model.
    static var bundledOpenAIModel: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OpenAIModel") as? String,
              !value.isEmpty else { return "gpt-5.6-luna" }
        return value
    }

    /// Bundled fallback for continuous speech-to-speech conversations.
    static var bundledOpenAIRealtimeModel: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OpenAIRealtimeModel") as? String,
              !value.isEmpty else { return "gpt-realtime" }
        return value
    }

    /// Effective user-selected model. A choice is never silently replaced:
    /// unsupported project access is surfaced by the OpenAI API so the owner
    /// can choose a different option in Settings.
    static var openAIModel: String {
        selectedOpenAIModel()
    }

    static var openAIRealtimeModel: String {
        selectedOpenAIRealtimeModel()
    }

    /// Orbit Chat's OpenAI model. Until the owner picks one for chat, chat
    /// keeps using the email scanning model, as it did before it had its own.
    static var openAIChatModel: String {
        selectedOpenAIChatModel()
    }

    /// Chat offers the newest models first. The email scanner keeps its own
    /// list, whose models are known to work with its structured requests.
    static let openAIChatModelChoices: [AIModelChoice] = [
        AIModelChoice(
            id: "gpt-6-luna",
            name: "GPT-6 Luna",
            detail: "Quick, low-cost answers for everyday questions",
            isRecommended: true,
            cost: .low
        ),
        AIModelChoice(
            id: "gpt-6-sol",
            name: "GPT-6 Sol",
            detail: "Most capable, for hard questions and planning",
            cost: .high
        ),
        AIModelChoice(
            id: "gpt-5.6-terra",
            name: "GPT-5.6 Terra",
            detail: "Balanced quality and cost",
            cost: .medium
        ),
        AIModelChoice(
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            detail: "Previous generation's most capable model",
            cost: .high
        ),
        AIModelChoice(
            id: "gpt-5.6-luna",
            name: "GPT-5.6 Luna",
            detail: "Previous generation's low-cost model",
            cost: .low
        ),
        AIModelChoice(
            id: "gpt-4o-mini",
            name: "GPT-4o mini",
            detail: "Fast and economical, without reasoning",
            cost: .low
        )
    ]

    static let openAITextModelChoices: [AIModelChoice] = [
        AIModelChoice(
            id: "gpt-5.6-terra",
            name: "GPT-5.6 Terra",
            detail: "Balanced quality and cost for daily use"
        ),
        AIModelChoice(
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            detail: "Highest quality for difficult questions"
        ),
        AIModelChoice(
            id: "gpt-5.6-luna",
            name: "GPT-5.6 Luna",
            detail: "Lowest-cost GPT-5.6 option for frequent scans",
            isRecommended: true
        ),
        AIModelChoice(
            id: "gpt-4o-mini",
            name: "GPT-4o mini",
            detail: "Fast, economical compatibility option"
        )
    ]

    static let openAIRealtimeModelChoices: [AIModelChoice] = [
        AIModelChoice(
            id: "gpt-realtime-2.1",
            name: "Realtime 2.1",
            detail: "Best reasoning and instruction following",
            isRecommended: true
        ),
        AIModelChoice(
            id: "gpt-realtime-2.1-mini",
            name: "Realtime 2.1 mini",
            detail: "Faster, lower-cost live voice"
        ),
        AIModelChoice(
            id: "gpt-realtime-1.5",
            name: "Realtime 1.5",
            detail: "Fast, reliable non-reasoning voice"
        ),
        AIModelChoice(
            id: "gpt-realtime",
            name: "Realtime (compatibility)",
            detail: "Existing compatibility option"
        )
    ]

    static func selectedOpenAIModel(defaults: UserDefaults = .standard) -> String {
        selectedValue(
            forKey: openAIModelPreferenceKey,
            fallback: bundledOpenAIModel,
            defaults: defaults
        )
    }

    static func selectedOpenAIRealtimeModel(defaults: UserDefaults = .standard) -> String {
        selectedValue(
            forKey: openAIRealtimeModelPreferenceKey,
            fallback: bundledOpenAIRealtimeModel,
            defaults: defaults
        )
    }

    static func selectedOpenAIChatModel(defaults: UserDefaults = .standard) -> String {
        selectedValue(
            forKey: openAIChatModelPreferenceKey,
            fallback: selectedOpenAIModel(defaults: defaults),
            defaults: defaults
        )
    }

    static func textModelChoices(including selected: String) -> [AIModelChoice] {
        choices(openAITextModelChoices, including: selected)
    }

    static func chatModelChoices(including selected: String) -> [AIModelChoice] {
        choices(openAIChatModelChoices, including: selected)
    }

    /// The chat choice for `id`, or a plain entry for a model set elsewhere.
    static func chatModelChoice(for id: String) -> AIModelChoice {
        chatModelChoices(including: id).first { $0.id == id }
            ?? AIModelChoice(id: id, name: id, detail: id)
    }

    static func realtimeModelChoices(including selected: String) -> [AIModelChoice] {
        choices(openAIRealtimeModelChoices, including: selected)
    }

    /// Minimum iOS shown in Settings/About.
    static let minimumOS = "17.0"

    private static func configuredURL(forInfoKey key: String) -> URL? {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !configured.isEmpty,
              let url = URL(string: configured),
              url.scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    private static func selectedValue(
        forKey key: String,
        fallback: String,
        defaults: UserDefaults
    ) -> String {
        let selected = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return selected.isEmpty ? fallback : selected
    }

    private static func choices(
        _ catalog: [AIModelChoice],
        including selected: String
    ) -> [AIModelChoice] {
        guard !selected.isEmpty, !catalog.contains(where: { $0.id == selected }) else {
            return catalog
        }
        return [
            AIModelChoice(
                id: selected,
                name: "Configured model",
                detail: selected
            )
        ] + catalog
    }
}

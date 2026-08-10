import Foundation

/// Central, non-secret application configuration.
///
/// Nothing sensitive lives here. The OpenAI key never ships in the app — the
/// client only knows how to reach *our* backend, which brokers AI requests.
enum AppConfig {
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

    /// Cost-efficient model used for email extraction and the in-app assistant.
    /// It supports Responses API Structured Outputs and can be overridden from
    /// Info.plist without changing source code.
    static var openAIModel: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OpenAIModel") as? String,
              !value.isEmpty else { return "gpt-4o-mini" }
        return value
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
}

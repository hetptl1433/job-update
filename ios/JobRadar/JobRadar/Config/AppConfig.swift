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

    /// Base URL for our backend. Configurable via the `APIBaseURL` Info.plist
    /// key so development / staging / production can be swapped without a code
    /// change. Falls back to the existing production backend.
    static var apiBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        return URL(string: configured ?? "https://job-update.vercel.app")!
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

    /// Minimum iOS shown in Settings/About.
    static let minimumOS = "17.0"
}

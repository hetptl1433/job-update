import AuthenticationServices
import Foundation
import UIKit

/// "Sign in with ChatGPT" support.
///
/// OpenAI identity is brokered through our backend (the app holds no OpenAI
/// secret): the app opens the backend's OAuth start URL in a secure web session,
/// the backend performs the OpenAI OAuth exchange, and redirects back into the
/// app with a short-lived session token.
///
/// This is gated behind `AppConfig.isChatGPTAuthConfigured`; until the backend
/// OAuth client exists, the UI explains it's coming rather than failing opaquely.
@MainActor
final class OpenAIAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    struct Result {
        var userID: String
        var email: String
        var fullName: String
        var sessionToken: String
    }

    func signIn() async throws -> Result {
        guard AppConfig.isChatGPTAuthConfigured else { throw AuthError.notConfigured }

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: "api/auth/openai/start"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "callback", value: "\(AppConfig.appURLScheme)://auth/openai")]
        guard let url = components?.url else { throw AuthError.underlying("Invalid sign-in URL.") }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(url: url, callbackURLScheme: AppConfig.appURLScheme) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.underlying(error.localizedDescription))
                    }
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            session = webSession
            webSession.start()
        }

        return try Self.parse(callback)
    }

    private static func parse(_ url: URL) throws -> Result {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
        let token = value("token")
        guard !token.isEmpty else { throw AuthError.underlying("Sign-in did not return a session.") }
        return Result(userID: value("sub"), email: value("email"), fullName: value("name"), sessionToken: token)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

import Foundation

/// Orchestrates Google authentication and secure token persistence.
///
/// Sensitive tokens are written only to the Keychain and are never logged.
/// The non-sensitive `UserSession` profile is persisted for fast restore.
@MainActor
final class AuthenticationManager {
    private let google: GoogleAuthProviding

    init(google: GoogleAuthProviding = DefaultGoogleAuthService()) {
        self.google = google
    }

    // MARK: Sign-in / restore

    func signIn() async throws -> UserSession {
        let result = try await google.signIn()
        return persist(result)
    }

    func restoreSession() async -> UserSession? {
        // Prefer a live SDK restore; fall back to the cached profile so returning
        // users skip onboarding even before the SDK finishes restoring.
        if let result = try? await google.restore() {
            return persist(result)
        }
        return UserSession.restore()
    }

    func requestScopes(_ scopes: [String]) async throws -> UserSession {
        let result = try await google.addScopes(scopes)
        return persist(result)
    }

    // MARK: Sign-out / disconnect

    func signOut() {
        google.signOut()
        clearTokens()
        UserSession.clear()
    }

    func disconnect() async {
        try? await google.disconnect()
        clearTokens()
        UserSession.clear()
    }

    @discardableResult
    func handleRedirect(_ url: URL) -> Bool { google.handle(url) }

    // MARK: Token storage

    private func persist(_ result: GoogleAuthResult) -> UserSession {
        // Tokens → Keychain only. Never UserDefaults, never logs.
        if !result.idToken.isEmpty { KeychainStore.set(result.idToken, for: KeychainKeys.googleIDToken) }
        if !result.accessToken.isEmpty { KeychainStore.set(result.accessToken, for: KeychainKeys.googleAccessToken) }

        let session = UserSession(
            userID: result.userID,
            email: result.email,
            fullName: result.fullName,
            avatarURLString: result.avatarURLString,
            grantedScopes: result.grantedScopes
        )
        session.persist()
        return session
    }

    private func clearTokens() {
        KeychainStore.remove(KeychainKeys.googleIDToken)
        KeychainStore.remove(KeychainKeys.googleAccessToken)
    }
}

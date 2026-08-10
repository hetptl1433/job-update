import Foundation

/// Orchestrates Google authentication and secure token persistence.
///
/// Sensitive tokens are written only to the Keychain and are never logged.
/// The non-sensitive `UserSession` profile is persisted for fast restore.
@MainActor
final class AuthenticationManager {
    private let google: GoogleAuthProviding

    init(google: GoogleAuthProviding? = nil) {
        self.google = google ?? DefaultGoogleAuthService()
    }

    // MARK: Sign-in / restore

    func signIn(requiredScopes: [String] = []) async throws -> UserSession {
        let result = try await google.signIn(additionalScopes: requiredScopes)
        return persist(result)
    }

    func restoreSession() async -> UserSession? {
        // The cached profile is the primary Orbit identity. Additional Gmail
        // sign-ins must never replace it just because they were authorized last.
        let cached = UserSession.restore()
        if let result = try? await google.restore(expectedUserID: cached?.userID) {
            return persist(result)
        }
        return cached
    }

    func requestScopes(_ scopes: [String]) async throws -> UserSession {
        guard let primary = UserSession.restore() else { throw AuthError.underlying("Sign in first.") }
        let result = try await google.addScopes(scopes, for: primary.userID)
        return persist(result)
    }

    /// Authorizes another Google account as a Gmail-only data source. It is
    /// intentionally not persisted as the Orbit identity.
    func connectAdditionalGmail() async throws -> EmailAccount {
        let result = try await google.signIn(additionalScopes: [GoogleScopes.gmailReadonly])
        guard result.grantedScopes.contains(GoogleScopes.gmailReadonly) else {
            if result.userID != UserSession.restore()?.userID { google.forgetUser(result.userID) }
            throw AuthError.underlying("Read-only Gmail access was not approved for this account.")
        }
        return EmailAccount(
            provider: .gmail,
            providerAccountID: result.userID,
            email: result.email,
            displayName: result.fullName
        )
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

    /// A fresh Google OAuth access token for calling Google REST APIs.
    func currentGoogleAccessToken() async -> String? {
        guard let primary = UserSession.restore() else { return nil }
        return await googleAccessToken(for: primary.userID)
    }

    /// A refreshed identity token for authenticated calls to Orbit's backend.
    /// Plaid credentials remain on that backend and never enter this token.
    func currentGoogleIDToken() async -> String? {
        guard let primary = UserSession.restore() else { return nil }
        if let fresh = await google.idToken(for: primary.userID), !fresh.isEmpty {
            KeychainStore.set(fresh, for: KeychainKeys.googleIDToken)
            return fresh
        }
        return KeychainStore.get(KeychainKeys.googleIDToken)
    }

    func googleAccessToken(for userID: String) async -> String? {
        if let fresh = await google.accessToken(for: userID), !fresh.isEmpty {
            if userID == UserSession.restore()?.userID {
                KeychainStore.set(fresh, for: KeychainKeys.googleAccessToken)
            }
            return fresh
        }
        // A cached token makes a short-lived restore usable while the SDK is
        // recovering, but only for the primary account.
        if userID == UserSession.restore()?.userID {
            return KeychainStore.get(KeychainKeys.googleAccessToken)
        }
        return nil
    }

    func forgetGoogleAccount(_ userID: String) { google.forgetUser(userID) }

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

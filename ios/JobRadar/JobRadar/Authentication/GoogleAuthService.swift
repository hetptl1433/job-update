import Foundation
import UIKit

/// Abstraction over Google authentication so the rest of the app never depends
/// on the concrete SDK. This makes the auth layer testable and lets the build
/// succeed whether or not the GoogleSignIn package is present.
///
/// Main-actor isolated: sign-in presents UI and the whole auth stack runs on
/// the main actor.
@MainActor
protocol GoogleAuthProviding: AnyObject {
    /// Interactive sign-in, optionally requesting product scopes up front.
    func signIn(additionalScopes: [String]) async throws -> GoogleAuthResult
    /// Silent restore of a previous session, if one exists.
    func restore(expectedUserID: String?) async throws -> GoogleAuthResult?
    /// Incrementally request additional scopes (e.g. Gmail, Calendar).
    func addScopes(_ scopes: [String], for userID: String) async throws -> GoogleAuthResult
    /// A fresh OAuth access token for one connected Google account.
    func accessToken(for userID: String) async -> String?
    /// A fresh Google identity token for authenticating to Orbit's backend.
    func idToken(for userID: String) async -> String?
    /// Removes a locally stored Google credential without revoking other users.
    func forgetUser(_ userID: String)
    /// Local sign-out (keeps the Google grant).
    func signOut()
    /// Clear the SDK's active local sign-in. Per-account credentials are
    /// removed separately so one mailbox is never accidentally revoked as another.
    func disconnect() async throws
    /// Handle the OAuth redirect URL. Returns true if the SDK consumed it.
    @discardableResult
    func handle(_ url: URL) -> Bool
}

// Common base identity scopes.
enum GoogleScopes {
    static let identity = ["email", "profile", "openid"]
    static let gmailReadonly = "https://www.googleapis.com/auth/gmail.readonly"
    static let calendarReadonly = "https://www.googleapis.com/auth/calendar.readonly"
}

#if canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn

/// Real implementation backed by the official GoogleSignIn SDK.
@MainActor
final class LiveGoogleAuthService: GoogleAuthProviding {
    init() { configureIfNeeded() }

    private func configureIfNeeded() {
        // The SDK auto-reads GIDClientID from Info.plist. If also provided via
        // AppConfig, set it explicitly to be safe.
        if GIDSignIn.sharedInstance.configuration == nil, let clientID = AppConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    func signIn(additionalScopes: [String]) async throws -> GoogleAuthResult {
        guard AppConfig.isGoogleConfigured || GIDSignIn.sharedInstance.configuration != nil else {
            throw AuthError.notConfigured
        }
        configureIfNeeded()
        let presenter = try rootViewController()
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: additionalScopes
            )
            store(result.user)
            return try makeResult(from: result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func restore(expectedUserID: String?) async throws -> GoogleAuthResult? {
        if let expectedUserID, let saved = storedUser(expectedUserID) {
            let user = try await refresh(saved)
            store(user)
            return try makeResult(from: user)
        }
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            guard expectedUserID == nil || user.userID == expectedUserID else { return nil }
            store(user)
            return try makeResult(from: user)
        } catch {
            return nil
        }
    }

    func addScopes(_ scopes: [String], for userID: String) async throws -> GoogleAuthResult {
        let presenter = try rootViewController()
        guard let user = storedUser(userID) ?? GIDSignIn.sharedInstance.currentUser,
              user.userID == userID else {
            throw AuthError.underlying("Reconnect your primary Google account first.")
        }
        do {
            let result = try await user.addScopes(scopes, presenting: presenter)
            store(result.user)
            return try makeResult(from: result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func accessToken(for userID: String) async -> String? {
        let current = GIDSignIn.sharedInstance.currentUser
        guard let user = storedUser(userID) ?? (current?.userID == userID ? current : nil) else { return nil }
        guard let refreshed = try? await refresh(user) else { return nil }
        store(refreshed)
        return refreshed.accessToken.tokenString
    }

    func idToken(for userID: String) async -> String? {
        let current = GIDSignIn.sharedInstance.currentUser
        guard let user = storedUser(userID) ?? (current?.userID == userID ? current : nil) else { return nil }
        guard let refreshed = try? await refresh(user) else { return nil }
        store(refreshed)
        return refreshed.idToken?.tokenString
    }

    func forgetUser(_ userID: String) { KeychainStore.remove(Self.userKey(userID)) }

    func signOut() { GIDSignIn.sharedInstance.signOut() }

    func disconnect() async throws {
        GIDSignIn.sharedInstance.signOut()
    }

    func handle(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }

    // MARK: Helpers

    private func makeResult(from user: GIDGoogleUser) throws -> GoogleAuthResult {
        let profile = user.profile
        return GoogleAuthResult(
            userID: user.userID ?? UUID().uuidString,
            email: profile?.email ?? "",
            fullName: profile?.name ?? "",
            avatarURLString: profile?.imageURL(withDimension: 200)?.absoluteString,
            idToken: user.idToken?.tokenString ?? "",
            accessToken: user.accessToken.tokenString,
            grantedScopes: user.grantedScopes ?? []
        )
    }

    private static func userKey(_ userID: String) -> String { "orbit.google.user.\(userID)" }

    private func store(_ user: GIDGoogleUser) {
        guard let userID = user.userID,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: user, requiringSecureCoding: true) else { return }
        KeychainStore.set(data, for: Self.userKey(userID))
    }

    private func storedUser(_ userID: String) -> GIDGoogleUser? {
        guard let data = KeychainStore.data(for: Self.userKey(userID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: GIDGoogleUser.self, from: data)
    }

    /// A cold launch can reach this before the network path is usable. One
    /// transient failure would otherwise drop callers onto the stale Keychain
    /// token, which is already expired and guarantees a 401.
    private func refresh(_ user: GIDGoogleUser, attempts: Int = 2) async throws -> GIDGoogleUser {
        var lastError: Error = AuthError.underlying("Could not refresh Google credentials.")
        for attempt in 0..<max(1, attempts) {
            do {
                return try await refreshOnce(user)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(600))
                }
            }
        }
        throw lastError
    }

    private func refreshOnce(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshed, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: refreshed ?? user) }
            }
        }
    }

    private func rootViewController() throws -> UIViewController {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard let root = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController else {
            throw AuthError.underlying("No window is available to present sign-in.")
        }
        return root
    }

    private static func mapError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.canceled.rawValue {
            return .cancelled
        }
        return .underlying(error.localizedDescription)
    }
}

typealias DefaultGoogleAuthService = LiveGoogleAuthService

#else

/// Honest fallback used only when the GoogleSignIn package is unavailable.
/// Production data is never simulated.
@MainActor
final class UnavailableGoogleAuthService: GoogleAuthProviding {
    func signIn(additionalScopes: [String]) async throws -> GoogleAuthResult {
        throw AuthError.sdkUnavailable
    }
    func restore(expectedUserID: String?) async throws -> GoogleAuthResult? { nil }
    func addScopes(_ newScopes: [String], for userID: String) async throws -> GoogleAuthResult {
        throw AuthError.sdkUnavailable
    }
    func accessToken(for userID: String) async -> String? { nil }
    func idToken(for userID: String) async -> String? { nil }
    func forgetUser(_ userID: String) {}
    func signOut() {}
    func disconnect() async throws {}
    func handle(_ url: URL) -> Bool { false }
}

typealias DefaultGoogleAuthService = UnavailableGoogleAuthService

#endif

import Foundation
import UIKit

/// Abstraction over Google authentication so the rest of the app never depends
/// on the concrete SDK. This makes the auth layer testable and lets the build
/// succeed whether or not the GoogleSignIn package is present.
protocol GoogleAuthProviding: AnyObject {
    /// Interactive sign-in. Requests only base identity scopes.
    func signIn() async throws -> GoogleAuthResult
    /// Silent restore of a previous session, if one exists.
    func restore() async throws -> GoogleAuthResult?
    /// Incrementally request additional scopes (e.g. Gmail, Calendar).
    func addScopes(_ scopes: [String]) async throws -> GoogleAuthResult
    /// Local sign-out (keeps the Google grant).
    func signOut()
    /// Fully revoke the app's access to the Google account.
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
import GoogleSignIn

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

    func signIn() async throws -> GoogleAuthResult {
        guard AppConfig.isGoogleConfigured || GIDSignIn.sharedInstance.configuration != nil else {
            throw AuthError.notConfigured
        }
        configureIfNeeded()
        let presenter = try rootViewController()
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            return try makeResult(from: result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func restore() async throws -> GoogleAuthResult? {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return try makeResult(from: user)
        } catch {
            return nil
        }
    }

    func addScopes(_ scopes: [String]) async throws -> GoogleAuthResult {
        let presenter = try rootViewController()
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.underlying("Not signed in.") }
        do {
            let result = try await user.addScopes(scopes, presenting: presenter)
            return try makeResult(from: result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signOut() { GIDSignIn.sharedInstance.signOut() }

    func disconnect() async throws {
        do { try await GIDSignIn.sharedInstance.disconnect() }
        catch { throw Self.mapError(error) }
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

/// Fallback used only when the GoogleSignIn package is unavailable. Simulates a
/// successful sign-in so the full app flow (routing, setup, restore, sign-out)
/// remains testable. Never used once the SDK resolves.
@MainActor
final class SimulatedGoogleAuthService: GoogleAuthProviding {
    private var restorable = false
    private var scopes = GoogleScopes.identity

    func signIn() async throws -> GoogleAuthResult {
        try await Task.sleep(nanoseconds: 400_000_000)
        restorable = true
        return sampleResult()
    }

    func restore() async throws -> GoogleAuthResult? {
        restorable ? sampleResult() : nil
    }

    func addScopes(_ newScopes: [String]) async throws -> GoogleAuthResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        scopes = Array(Set(scopes + newScopes))
        return sampleResult()
    }

    func signOut() { restorable = false }
    func disconnect() async throws { restorable = false; scopes = GoogleScopes.identity }
    func handle(_ url: URL) -> Bool { false }

    private func sampleResult() -> GoogleAuthResult {
        GoogleAuthResult(
            userID: "simulated-user",
            email: "het@gmail.com",
            fullName: "Het Patel",
            avatarURLString: nil,
            idToken: "simulated-id-token",
            accessToken: "simulated-access-token",
            grantedScopes: scopes
        )
    }
}

typealias DefaultGoogleAuthService = SimulatedGoogleAuthService

#endif

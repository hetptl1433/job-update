import Foundation

/// The signed-in user's non-sensitive profile. Tokens are NOT stored here —
/// they live in the Keychain. This is safe to keep in memory and persist to
/// UserDefaults for fast session restoration.
struct UserSession: Codable, Equatable {
    var userID: String
    var email: String
    var fullName: String
    var avatarURLString: String?
    var grantedScopes: [String]

    var firstName: String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }

    static let storageKey = "orbit.userSession"

    /// Persist the non-sensitive profile for fast restore.
    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func restore() -> UserSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// Result of a Google authentication exchange.
struct GoogleAuthResult {
    var userID: String
    var email: String
    var fullName: String
    var avatarURLString: String?
    var idToken: String
    var accessToken: String
    var grantedScopes: [String]
}

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case sdkUnavailable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Google Sign-In isn't configured yet. Add your OAuth client ID (GIDClientID) in Info.plist."
        case .cancelled:
            "Sign-in was cancelled."
        case .sdkUnavailable:
            "The Google Sign-In SDK is not available in this build."
        case let .underlying(message):
            message
        }
    }
}

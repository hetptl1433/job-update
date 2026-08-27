import Foundation

enum EmailProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case gmail
    case outlook

    var id: String { rawValue }
    var label: String { self == .gmail ? "Gmail" : "Outlook" }
    var systemImage: String { self == .gmail ? "envelope" : "envelope.badge" }
}

enum EmailAccountFilter: String, CaseIterable, Identifiable {
    case all
    case gmail
    case outlook

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All Accounts"
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        }
    }

    func includes(_ provider: EmailProviderType) -> Bool {
        self == .all || rawValue == provider.rawValue
    }
}

/// One authorized mailbox. This is separate from the single primary Orbit
/// identity and is safe to persist because it contains no OAuth tokens.
struct EmailAccount: Codable, Identifiable, Equatable, Hashable, Sendable {
    var provider: EmailProviderType
    var providerAccountID: String
    var email: String
    var displayName: String
    var isPrimaryIdentity: Bool

    var id: String { "\(provider.rawValue):\(providerAccountID)" }

    init(
        provider: EmailProviderType,
        providerAccountID: String,
        email: String,
        displayName: String,
        isPrimaryIdentity: Bool = false
    ) {
        self.provider = provider
        self.providerAccountID = providerAccountID
        self.email = email
        self.displayName = displayName
        self.isPrimaryIdentity = isPrimaryIdentity
    }

    var userID: String { providerAccountID }
    var fullName: String { displayName }

    private enum CodingKeys: String, CodingKey {
        case provider, providerAccountID, email, displayName, isPrimaryIdentity
        case legacyUserID = "userID"
        case legacyFullName = "fullName"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(EmailProviderType.self, forKey: .provider) ?? .gmail
        email = try values.decode(String.self, forKey: .email)
        providerAccountID = try values.decodeIfPresent(String.self, forKey: .providerAccountID)
            ?? values.decodeIfPresent(String.self, forKey: .legacyUserID)
            ?? email
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
            ?? values.decodeIfPresent(String.self, forKey: .legacyFullName)
            ?? ""
        isPrimaryIdentity = try values.decodeIfPresent(Bool.self, forKey: .isPrimaryIdentity) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(provider, forKey: .provider)
        try values.encode(providerAccountID, forKey: .providerAccountID)
        try values.encode(email, forKey: .email)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(isPrimaryIdentity, forKey: .isPrimaryIdentity)
    }
}

/// Provider-neutral message used by the repository and AI layer. Provider API
/// payloads are normalized into this type before the rest of Orbit sees them.
struct EmailMessage: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var provider: EmailProviderType
    var accountID: String
    var accountEmail: String
    var threadID: String
    var senderName: String
    var senderEmail: String
    var subject: String
    var preview: String
    var body: String
    var receivedDate: Date
    var isRead: Bool
    var providerImportance: String?

    var forModel: String {
        let source = body.isEmpty ? preview : body
        let clipped = String(source.prefix(2_200))
        let date = ISO8601DateFormatter().string(from: receivedDate)
        return """
        MESSAGE
        id: \(id)
        provider: \(provider.rawValue)
        mailbox: \(accountEmail)
        from_name: \(senderName)
        from_email: \(senderEmail)
        subject: \(subject)
        date: \(date)
        is_read: \(isRead)
        body: \(clipped)
        """
    }
}

/// One bounded provider result. `hasMore` is authoritative: when true Orbit
/// records the returned IDs but deliberately keeps the prior cursor so the
/// remaining backlog is discoverable on the next scan.
struct EmailFetchBatch: Equatable, Sendable {
    var messages: [EmailMessage]
    var hasMore: Bool
}

protocol EmailProviderService {
    var provider: EmailProviderType { get }
    func recentMessageBatch(
        account: EmailAccount,
        maxResults: Int,
        token: String,
        receivedAfter: Date?,
        excludingMessageIDs: Set<String>
    ) async throws -> EmailFetchBatch
}

extension EmailProviderService {
    func recentMessages(
        account: EmailAccount,
        maxResults: Int,
        token: String
    ) async throws -> [EmailMessage] {
        try await recentMessageBatch(
            account: account,
            maxResults: maxResults,
            token: token,
            receivedAfter: nil,
            excludingMessageIDs: []
        ).messages
    }
}

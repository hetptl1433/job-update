import Foundation

/// Modular Gmail access. The client never parses raw Gmail directly for AI —
/// classification/summarization happens on the backend, which returns compact,
/// already-filtered messages. Read-only is the initial priority.
protocol GmailService {
    func importantMessages() async throws -> [InboxMessage]
    func search(_ query: String) async throws -> [InboxMessage]
}

/// Backend-backed Gmail service. Endpoints are implemented server-side; until
/// then calls fail and the repository shows an honest empty state.
struct BackendGmailService: GmailService {
    let api: APIClient

    func importantMessages() async throws -> [InboxMessage] {
        let envelope = try await api.get("api/mobile/gmail/important", as: InboxEnvelope.self)
        return envelope.messages.map(InboxMessage.init(dto:))
    }

    func search(_ query: String) async throws -> [InboxMessage] {
        let envelope = try await api.get("api/mobile/gmail/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")", as: InboxEnvelope.self)
        return envelope.messages.map(InboxMessage.init(dto:))
    }
}

/// Observable repository the Inbox and Home screens read from.
@MainActor
final class GmailRepository: ObservableObject {
    @Published private(set) var state: LoadState<[InboxMessage]> = .disconnected
    private(set) var connected = false
    private let service: GmailService

    init(api: APIClient) {
        self.service = BackendGmailService(api: api)
    }

    func markConnected(_ value: Bool) {
        connected = value
        if !value { state = .disconnected }
    }

    func refresh() async {
        guard connected else { state = .disconnected; return }
        state = .loading
        do {
            let messages = try await service.importantMessages()
            state = messages.isEmpty ? .empty : .loaded(messages)
        } catch {
            // Backend classification not available yet — honest empty, not fake data.
            state = .empty
        }
    }

    func messages(in section: InboxSection) -> [InboxMessage] {
        (state.value ?? []).filter { $0.section == section }
    }
}

// MARK: - Wire format

struct InboxEnvelope: Decodable {
    let messages: [GmailMessageDTO]
}

struct GmailMessageDTO: Decodable {
    let id: String
    let sender: String
    let subject: String
    let summary: String
    let receivedAt: String
    let importance: Int
    let actionRequired: Bool
    let section: String
    let isRead: Bool?
    let threadID: String?
    let labels: [String]?
}

extension InboxMessage {
    init(dto: GmailMessageDTO) {
        self.init(
            id: dto.id,
            sender: dto.sender,
            subject: dto.subject,
            aiSummary: dto.summary,
            receivedAt: ISO8601DateFormatter().date(from: dto.receivedAt) ?? .now,
            importance: AttentionImportance(rawValue: dto.importance) ?? .normal,
            actionRequired: dto.actionRequired,
            section: InboxSection(rawValue: dto.section) ?? .everythingElse,
            isRead: dto.isRead ?? false,
            threadID: dto.threadID,
            labels: dto.labels ?? []
        )
    }
}

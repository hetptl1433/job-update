import Foundation

/// A single fetched Gmail message, reduced to what we need for AI processing.
struct GmailRawMessage: Identifiable, Equatable {
    let id: String
    var threadID: String
    var from: String
    var subject: String
    var date: Date?
    var snippet: String
    var body: String

    /// Compact text handed to the model (kept short to limit tokens/cost).
    var forModel: String {
        let trimmedBody = body.isEmpty ? snippet : body
        let clipped = String(trimmedBody.prefix(1500))
        return "id: \(id)\nfrom: \(from)\nsubject: \(subject)\ndate: \(date?.formatted() ?? "")\nbody: \(clipped)"
    }
}

/// Calls the Gmail REST API directly with the user's OAuth access token.
/// Read-only. No message content is logged.
struct GmailAPIClient {
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    func recentMessages(query: String, maxResults: Int, token: String) async throws -> [GmailRawMessage] {
        let ids = try await listMessageIDs(query: query, maxResults: maxResults, token: token)
        var messages: [GmailRawMessage] = []
        // Fetch sequentially to stay well within rate limits for a manual refresh.
        for id in ids {
            if let message = try? await fetchMessage(id: id, token: token) {
                messages.append(message)
            }
        }
        return messages
    }

    // MARK: List

    private struct ListResponse: Decodable {
        let messages: [Ref]?
        struct Ref: Decodable { let id: String; let threadId: String }
    }

    private func listMessageIDs(query: String, maxResults: Int, token: String) async throws -> [String] {
        var components = URLComponents(url: base.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        let data = try await get(components.url!, token: token)
        return (try JSONDecoder().decode(ListResponse.self, from: data)).messages?.map(\.id) ?? []
    }

    // MARK: Get

    private struct MessageResponse: Decodable {
        let id: String
        let threadId: String
        let snippet: String?
        let internalDate: String?
        let payload: Payload?
        struct Payload: Decodable {
            let headers: [Header]?
            let mimeType: String?
            let body: Body?
            let parts: [Payload]?
        }
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let data: String? }
    }

    private func fetchMessage(id: String, token: String) async throws -> GmailRawMessage {
        let url = base.appending(path: "messages/\(id)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let data = try await get(components.url!, token: token)
        let message = try JSONDecoder().decode(MessageResponse.self, from: data)

        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }
        let date = message.internalDate.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0 / 1000) }

        return GmailRawMessage(
            id: message.id,
            threadID: message.threadId,
            from: header("From"),
            subject: header("Subject"),
            date: date,
            snippet: message.snippet ?? "",
            body: Self.extractPlainText(from: message.payload)
        )
    }

    /// Walks the MIME tree for the first text/plain part and base64url-decodes it.
    private static func extractPlainText(from payload: MessageResponse.Payload?) -> String {
        guard let payload else { return "" }
        if payload.mimeType == "text/plain", let encoded = payload.body?.data, let text = decode(encoded) {
            return text
        }
        for part in payload.parts ?? [] {
            let text = extractPlainText(from: part)
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func decode(_ base64url: String) -> String? {
        var s = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: HTTP

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server(status: -1, message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw APIError.server(status: http.statusCode, message: message ?? "Gmail request failed.")
        }
        return data
    }
}

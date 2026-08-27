import Foundation

/// Configuration errors returned by Google that the user can resolve outside
/// the app. Keeping this separate lets the UI offer the right recovery action
/// instead of displaying Google's long raw server response.
enum GmailAPIError: LocalizedError {
    case serviceDisabled(projectID: String?)

    var errorDescription: String? {
        switch self {
        case .serviceDisabled(let projectID):
            let project = projectID.map { " for Google Cloud project \($0)" } ?? ""
            return "Gmail is connected, but the Gmail API is not enabled\(project). Enable it in Google Cloud, wait a few minutes, then scan Gmail again."
        }
    }

    var recoveryURL: URL? {
        switch self {
        case .serviceDisabled(let projectID):
            var components = URLComponents(string: "https://console.cloud.google.com/apis/library/gmail.googleapis.com")
            if let projectID {
                components?.queryItems = [URLQueryItem(name: "project", value: projectID)]
            }
            return components?.url
        }
    }
}

/// Calls the Gmail REST API directly with the user's OAuth access token.
/// Read-only. No message content is logged.
struct GmailAPIClient: EmailProviderService {
    let provider: EmailProviderType = .gmail
    private let base: URL
    private let session: URLSession

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    ) {
        self.session = session
        self.base = baseURL
    }

    func recentMessageBatch(
        account: EmailAccount,
        maxResults: Int,
        token: String,
        receivedAfter: Date?,
        excludingMessageIDs: Set<String>
    ) async throws -> EmailFetchBatch {
        var query = "newer_than:60d -category:promotions -category:social {application applied recruiter hiring interview assessment \"next steps\" offer position candidate \"not moving forward\" \"thank you for your interest\"}"
        if let receivedAfter {
            query += " after:\(Int(receivedAfter.timeIntervalSince1970))"
        }
        return try await recentMessageBatch(
            query: query,
            maxResults: maxResults,
            token: token,
            account: account,
            excludingMessageIDs: excludingMessageIDs
        )
    }

    func recentMessageBatch(
        query: String,
        maxResults: Int,
        token: String,
        account: EmailAccount,
        excludingMessageIDs: Set<String> = []
    ) async throws -> EmailFetchBatch {
        let limit = min(max(maxResults, 1), 50)
        var unseenIDs: [String] = []
        var pageToken: String?
        var visitedPageTokens = Set<String>()

        // Gmail returns newest IDs first. Walk pages until there are `limit + 1`
        // unseen IDs or the query is exhausted. That extra ID is how Orbit knows
        // it must keep the old cursor and drain another bounded batch later.
        repeat {
            if let pageToken, !visitedPageTokens.insert(pageToken).inserted {
                throw APIError.decoding("Gmail returned a repeated page while scanning messages.")
            }
            let page = try await listMessagePage(
                query: query,
                maxResults: 100,
                pageToken: pageToken,
                token: token
            )
            for id in page.ids where !excludingMessageIDs.contains(
                "gmail:\(account.providerAccountID):\(id)"
            ) {
                unseenIDs.append(id)
                if unseenIDs.count > limit { break }
            }
            pageToken = page.nextPageToken
        } while unseenIDs.count <= limit && pageToken != nil

        let hasMore = unseenIDs.count > limit
        let selectedIDs = Array(unseenIDs.prefix(limit))
        guard !selectedIDs.isEmpty else {
            return EmailFetchBatch(messages: [], hasMore: false)
        }

        // Full messages are independent. Fetch concurrently to avoid making a
        // 40-message sync take 40 network round trips in series. A partial body
        // failure fails the whole batch so its cursor can never skip that ID.
        let indexed = try await withThrowingTaskGroup(of: (Int, EmailMessage).self) { group in
            for (index, id) in selectedIDs.enumerated() {
                group.addTask {
                    (index, try await fetchMessage(id: id, token: token, account: account))
                }
            }
            var values: [(Int, EmailMessage)] = []
            for try await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return EmailFetchBatch(messages: indexed, hasMore: hasMore)
    }

    // MARK: List

    private struct ListResponse: Decodable {
        let messages: [Ref]?
        let nextPageToken: String?
        struct Ref: Decodable { let id: String; let threadId: String }
    }

    private func listMessagePage(
        query: String,
        maxResults: Int,
        pageToken: String?,
        token: String
    ) async throws -> (ids: [String], nextPageToken: String?) {
        var components = URLComponents(url: base.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        let data = try await get(components.url!, token: token)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return (response.messages?.map(\.id) ?? [], response.nextPageToken)
    }

    // MARK: Get

    private struct MessageResponse: Decodable {
        let id: String
        let threadId: String
        let labelIds: [String]?
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

    private func fetchMessage(id: String, token: String, account: EmailAccount) async throws -> EmailMessage {
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

        let sender = Self.parseAddress(header("From"))
        let labels = Set(message.labelIds ?? [])
        return EmailMessage(
            id: "gmail:\(account.providerAccountID):\(message.id)",
            provider: .gmail,
            accountID: account.id,
            accountEmail: account.email,
            threadID: "gmail:\(account.providerAccountID):\(message.threadId)",
            senderName: sender.name,
            senderEmail: sender.email,
            subject: header("Subject"),
            preview: message.snippet ?? "",
            body: Self.extractPlainText(from: message.payload),
            receivedDate: date ?? .distantPast,
            isRead: !labels.contains("UNREAD"),
            providerImportance: labels.contains("IMPORTANT") ? "high" : nil
        )
    }

    private static func parseAddress(_ value: String) -> (name: String, email: String) {
        let pattern = #"^\s*(.*?)\s*<([^>]+)>\s*$"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let nameRange = Range(match.range(at: 1), in: value),
           let emailRange = Range(match.range(at: 2), in: value) {
            let name = String(value[nameRange]).trimmingCharacters(in: CharacterSet(charactersIn: " \"") )
            return (name.isEmpty ? String(value[emailRange]) : name, String(value[emailRange]))
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed, trimmed.contains("@") ? trimmed : "")
    }

    /// Prefer plain text, then fall back to a cleaned HTML body. Gmail messages
    /// can place content on the root payload or several levels down the MIME tree.
    private static func extractPlainText(from payload: MessageResponse.Payload?) -> String {
        guard let payload else { return "" }
        if let plain = firstDecodedPart(in: payload, mimeType: "text/plain") { return clean(plain) }
        if let html = firstDecodedPart(in: payload, mimeType: "text/html") { return cleanHTML(html) }
        if let encoded = payload.body?.data, let text = decode(encoded) { return clean(text) }
        return (payload.parts ?? []).lazy.map(extractPlainText).first { !$0.isEmpty } ?? ""
    }

    private static func firstDecodedPart(in payload: MessageResponse.Payload, mimeType: String) -> String? {
        if payload.mimeType?.lowercased() == mimeType,
           let encoded = payload.body?.data,
           let value = decode(encoded) {
            return value
        }
        for part in payload.parts ?? [] {
            if let value = firstDecodedPart(in: part, mimeType: mimeType) { return value }
        }
        return nil
    }

    private static func decode(_ base64url: String) -> String? {
        var s = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func cleanHTML(_ value: String) -> String {
        let withoutStyle = value.replacingOccurrences(
            of: "(?is)<(style|script)[^>]*>.*?</\\1>", with: " ", options: .regularExpression
        )
        let withoutTags = withoutStyle.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        return clean(
            withoutTags
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
        )
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "[\\t\\r ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: HTTP

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server(status: -1, message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            if http.statusCode == 401 {
                throw APIError.server(status: 401, message: "Your Google session expired. Reconnect Gmail and try again.")
            }
            if http.statusCode == 403 {
                if Self.isServiceDisabled(message) {
                    throw GmailAPIError.serviceDisabled(projectID: Self.projectID(in: message))
                }
                throw APIError.server(status: 403, message: message ?? "Gmail access was not granted. Enable the Gmail API and approve read-only access.")
            }
            throw APIError.server(status: http.statusCode, message: message ?? "Gmail request failed.")
        }
        return data
    }

    private static func isServiceDisabled(_ message: String?) -> Bool {
        guard let value = message?.lowercased() else { return false }
        return value.contains("gmail api has not been used") ||
            (value.contains("gmail.googleapis.com") && value.contains("disabled"))
    }

    private static func projectID(in message: String?) -> String? {
        guard let message,
              let expression = try? NSRegularExpression(
                pattern: #"project(?:=|\s+)(\d+)"#,
                options: [.caseInsensitive]
              ) else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = expression.firstMatch(in: message, range: range),
              let swiftRange = Range(match.range(at: 1), in: message) else { return nil }
        return String(message[swiftRange])
    }
}

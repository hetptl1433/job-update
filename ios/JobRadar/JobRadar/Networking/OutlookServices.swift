import Foundation

enum MicrosoftGraphError: LocalizedError {
    case unauthorized
    case server(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "The Microsoft session expired. Reconnect Outlook and try again."
        case .server(_, let message): message
        case .invalidResponse(let message): "Microsoft Graph returned unexpected data: \(message)"
        }
    }
}

private enum MicrosoftGraph {
    static func get(
        _ url: URL,
        token: String,
        preferUTC: Bool = false,
        preferImmutableIDs: Bool = false,
        session: URLSession = .shared
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var preferences: [String] = []
        if preferUTC { preferences.append("outlook.timezone=\"UTC\"") }
        if preferImmutableIDs { preferences.append("IdType=\"ImmutableId\"") }
        if !preferences.isEmpty {
            request.setValue(preferences.joined(separator: ", "), forHTTPHeaderField: "Prefer")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftGraphError.invalidResponse("Missing HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw MicrosoftGraphError.unauthorized }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
                ?? "Microsoft Graph request failed (\(http.statusCode))."
            throw MicrosoftGraphError.server(http.statusCode, message)
        }
        return data
    }

    static func date(_ value: String) -> Date? {
        if let result = fractional.date(from: value) { return result }
        if let result = internet.date(from: value) { return result }
        let normalized = value.hasSuffix("Z") ? value : value + "Z"
        if let result = fractional.date(from: normalized) { return result }
        return internet.date(from: normalized)
    }

    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let internet = ISO8601DateFormatter()
}

struct OutlookMailService: EmailProviderService {
    let provider: EmailProviderType = .outlook
    private let base: URL
    private let session: URLSession

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://graph.microsoft.com/v1.0/me/messages")!
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
        let limit = min(max(maxResults, 1), 50)
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
        let since = max(receivedAfter ?? sixtyDaysAgo, sixtyDaysAgo)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "id,conversationId,from,subject,bodyPreview,receivedDateTime,isRead,importance"),
            URLQueryItem(name: "$filter", value: "receivedDateTime ge \(MicrosoftGraph.fractional.string(from: since))"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$top", value: "100")
        ]
        var nextURL = components.url
        var unseen: [EmailMessage] = []
        var visitedURLs = Set<URL>()

        // Follow Graph's nextLink until there is one more unseen message than
        // this bounded batch can process, or until the query is truly exhausted.
        // This prevents known messages on page one from hiding an older backlog.
        while let url = nextURL, unseen.count <= limit {
            guard visitedURLs.insert(url).inserted else {
                throw MicrosoftGraphError.invalidResponse(
                    "Microsoft Graph returned a repeated page while scanning messages."
                )
            }
            let data = try await MicrosoftGraph.get(
                url,
                token: token,
                preferImmutableIDs: true,
                session: session
            )
            let response: Response
            do { response = try JSONDecoder().decode(Response.self, from: data) }
            catch { throw MicrosoftGraphError.invalidResponse(error.localizedDescription) }

            for message in response.value {
                guard let mapped = map(
                    message,
                    account: account,
                    excludingMessageIDs: excludingMessageIDs
                ) else { continue }
                unseen.append(mapped)
                if unseen.count > limit { break }
            }
            nextURL = response.nextLink.flatMap { URL(string: $0) }
        }

        return EmailFetchBatch(
            messages: Array(unseen.prefix(limit)),
            hasMore: unseen.count > limit
        )
    }

    private struct Response: Decodable {
        let value: [Message]
        let nextLink: String?

        private enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }

        struct Message: Decodable {
            let id: String
            let conversationId: String?
            let from: Recipient?
            let subject: String?
            let bodyPreview: String?
            let receivedDateTime: String
            let isRead: Bool?
            let importance: String?
        }
        struct Recipient: Decodable { let emailAddress: Address }
        struct Address: Decodable { let name: String?; let address: String? }
    }

    private func map(
        _ message: Response.Message,
        account: EmailAccount,
        excludingMessageIDs: Set<String>
    ) -> EmailMessage? {
        guard let date = MicrosoftGraph.date(message.receivedDateTime) else { return nil }
        let sender = message.from?.emailAddress
        let messageID = "outlook:\(account.providerAccountID):\(message.id)"
        guard !excludingMessageIDs.contains(messageID) else { return nil }
        return EmailMessage(
            id: messageID,
            provider: .outlook,
            accountID: account.id,
            accountEmail: account.email,
            threadID: "outlook:\(account.providerAccountID):\(message.conversationId ?? message.id)",
            senderName: sender?.name ?? sender?.address ?? "Unknown sender",
            senderEmail: sender?.address ?? "",
            subject: message.subject ?? "(no subject)",
            preview: message.bodyPreview ?? "",
            body: message.bodyPreview ?? "",
            receivedDate: date,
            isRead: message.isRead ?? false,
            providerImportance: message.importance
        )
    }
}

struct OutlookCalendarService: CalendarProviderService {
    let provider: CalendarProviderType = .outlook
    let account: EmailAccount
    private let base = URL(string: "https://graph.microsoft.com/v1.0/me/calendarView")!

    func upcomingEvents(token: String?) async throws -> [UnifiedCalendarEvent] {
        guard let token, !token.isEmpty else { throw MicrosoftGraphError.unauthorized }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: MicrosoftGraph.fractional.string(from: now)),
            URLQueryItem(name: "endDateTime", value: MicrosoftGraph.fractional.string(from: end)),
            URLQueryItem(name: "$select", value: "id,subject,start,end,location,bodyPreview,onlineMeeting,webLink,isAllDay,isCancelled"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: "50")
        ]
        let data = try await MicrosoftGraph.get(components.url!, token: token, preferUTC: true)
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw MicrosoftGraphError.invalidResponse(error.localizedDescription) }

        return response.value.compactMap { event in
            guard event.isCancelled != true,
                  let start = MicrosoftGraph.date(event.start.dateTime) else { return nil }
            let title = event.subject?.isEmpty == false ? event.subject! : "Untitled event"
            let lower = title.lowercased()
            let important = ["interview", "recruiter", "assessment", "hiring", "candidate", "follow-up", "deadline"]
                .contains { lower.contains($0) }
            return UnifiedCalendarEvent(
                id: "outlook:\(account.providerAccountID):\(event.id)",
                provider: .outlook,
                calendarID: account.id,
                title: title,
                start: start,
                end: MicrosoftGraph.date(event.end.dateTime),
                location: event.location?.displayName,
                notes: event.bodyPreview,
                meetingURL: event.onlineMeeting?.joinUrl.flatMap(URL.init(string:))
                    ?? event.webLink.flatMap(URL.init(string:)),
                isAllDay: event.isAllDay ?? false,
                relatedJobApplicationID: nil,
                isImportant: important
            )
        }
        .sorted { $0.start < $1.start }
    }

    private struct Response: Decodable {
        let value: [Event]
        struct Event: Decodable {
            let id: String
            let subject: String?
            let start: TimeValue
            let end: TimeValue
            let location: Location?
            let bodyPreview: String?
            let onlineMeeting: OnlineMeeting?
            let webLink: String?
            let isAllDay: Bool?
            let isCancelled: Bool?
        }
        struct TimeValue: Decodable { let dateTime: String; let timeZone: String? }
        struct Location: Decodable { let displayName: String? }
        struct OnlineMeeting: Decodable { let joinUrl: String? }
    }
}

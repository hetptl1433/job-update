import Foundation

enum GoogleCalendarAPIError: LocalizedError {
    case serviceDisabled(projectID: String?)

    var errorDescription: String? {
        switch self {
        case .serviceDisabled(let projectID):
            let project = projectID.map { " for Google Cloud project \($0)" } ?? ""
            return "Google Calendar is connected, but the Calendar API is not enabled\(project). Enable it in Google Cloud, wait a few minutes, then try again."
        }
    }

    var recoveryURL: URL? {
        switch self {
        case .serviceDisabled(let projectID):
            var components = URLComponents(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")
            if let projectID { components?.queryItems = [URLQueryItem(name: "project", value: projectID)] }
            return components?.url
        }
    }
}

/// Minimal read-only Google Calendar client for the primary Orbit identity.
struct GoogleCalendarAPIClient: CalendarProviderService {
    let provider: CalendarProviderType = .google
    private let eventsURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!

    func upcomingEvents(token: String?) async throws -> [UnifiedCalendarEvent] {
        guard let token, !token.isEmpty else {
            throw APIError.server(status: 401, message: "Reconnect Google Calendar and try again.")
        }
        return try await upcomingEvents(token: token)
    }

    func upcomingEvents(token: String, days: Int = 14, maxResults: Int = 30) async throws -> [CalendarEvent] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: max(days, 1), to: now) ?? now
        var components = URLComponents(url: eventsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: Self.apiDate(now)),
            URLQueryItem(name: "timeMax", value: Self.apiDate(end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: String(min(max(maxResults, 1), 100))),
            URLQueryItem(name: "fields", value: "items(id,status,summary,start,end,location,description,hangoutLink)")
        ]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        let payload = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (payload.items ?? []).compactMap(Self.map).sorted { $0.start < $1.start }
    }

    private struct EventsResponse: Decodable {
        let items: [Item]?
        struct Item: Decodable {
            let id: String
            let status: String?
            let summary: String?
            let start: TimeValue
            let end: TimeValue?
            let location: String?
            let description: String?
            let hangoutLink: String?
        }
        struct TimeValue: Decodable {
            let dateTime: String?
            let date: String?
        }
    }

    private static func map(_ item: EventsResponse.Item) -> CalendarEvent? {
        guard item.status != "cancelled", let start = date(item.start) else { return nil }
        let title = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title?.isEmpty == false ? title! : "Untitled event"
        let lower = resolvedTitle.lowercased()
        let jobRelated = ["interview", "recruiter", "assessment", "hiring", "candidate", "follow-up", "deadline"]
            .contains { lower.contains($0) }
        return UnifiedCalendarEvent(
            id: "google:\(item.id)",
            provider: .google,
            calendarID: "primary",
            title: resolvedTitle,
            start: start,
            end: item.end.flatMap(date),
            location: item.location,
            notes: item.description,
            meetingURL: item.hangoutLink.flatMap(URL.init(string:)),
            isAllDay: item.start.date != nil,
            relatedJobApplicationID: nil,
            isImportant: jobRelated
        )
    }

    private static func date(_ value: EventsResponse.TimeValue) -> Date? {
        if let value = value.dateTime {
            if let result = fractionalDateFormatter.date(from: value) { return result }
            return internetDateFormatter.date(from: value)
        }
        guard let value = value.date else { return nil }
        return dayFormatter.date(from: value)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Google Calendar did not return a valid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            if http.statusCode == 401 {
                throw APIError.server(status: 401, message: "Your primary Google session expired. Reconnect Calendar and try again.")
            }
            if http.statusCode == 403, isServiceDisabled(message) {
                throw GoogleCalendarAPIError.serviceDisabled(projectID: projectID(in: message))
            }
            throw APIError.server(status: http.statusCode, message: message ?? "Google Calendar request failed.")
        }
    }

    private static func isServiceDisabled(_ message: String?) -> Bool {
        guard let value = message?.lowercased() else { return false }
        return value.contains("calendar api has not been used") ||
            (value.contains("calendar-json.googleapis.com") && value.contains("disabled"))
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

    private static func apiDate(_ date: Date) -> String { fractionalDateFormatter.string(from: date) }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

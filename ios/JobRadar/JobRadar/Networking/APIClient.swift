import Foundation

/// Errors surfaced by the networking layer.
enum APIError: LocalizedError {
    case badURL
    case server(status: Int, message: String?)
    case decoding(String)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .badURL: "The request address was invalid."
        case let .server(status, message): message ?? "The server rejected the request (\(status))."
        case let .decoding(detail): "Unexpected response from the server: \(detail)"
        case let .notConfigured(detail): detail
        }
    }
}

/// Thin async client for the existing job-tracker and push backend. Gmail uses
/// Google's read-only API; the personal-development AI mode is isolated in
/// `OpenAIClient` so it can be replaced by a production backend broker.
final class APIClient {
    let baseURL: URL?
    private let session: URLSession

    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Generic requests

    func get<Response: Decodable>(_ path: String, as type: Response.Type) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<Data>.none, as: type)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await send(path: path, method: "POST", body: data, as: type)
    }

    private func post<Body: Encodable, Response: Decodable>(
        pathComponents: [String], body: Body, as type: Response.Type
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await send(
            url: try url(forPathComponents: pathComponents),
            method: "POST",
            body: data,
            as: type
        )
    }

    func delete<Response: Decodable>(_ path: String, as type: Response.Type) async throws -> Response {
        try await send(path: path, method: "DELETE", body: Optional<Data>.none, as: type)
    }

    private func send<Response: Decodable>(
        path: String, method: String, body: Data?, as type: Response.Type
    ) async throws -> Response {
        try await send(url: try url(for: path), method: method, body: body, as: type)
    }

    private func send<Response: Decodable>(
        url: URL, method: String, body: Data?, as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: Job tracker (existing backend contract)

    func fetchApplications() async throws -> [JobApplicationDTO] {
        try await get("api/tracker", as: TrackerEnvelope.self).data
    }

    func saveApplications(_ applications: [JobApplicationDTO]) async throws {
        var request = URLRequest(url: try url(for: "api/tracker"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(applications)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func registerDeviceToken(_ token: String) async throws {
        struct Payload: Encodable { let token: String; let platform: String }
        struct Empty: Decodable {}
        _ = try? await post("api/mobile/push/register", body: Payload(token: token, platform: "ios"), as: Empty.self)
    }

    // MARK: Finance (Plaid is server-side only)

    func createPlaidHostedLink() async throws -> PlaidHostedLinkLaunch {
        struct Payload: Encodable { let platform = "ios" }
        return try await post(
            "api/plaid/hosted-link",
            body: Payload(),
            as: PlaidHostedLinkLaunch.self
        )
    }

    func fetchPlaidHostedLinkStatus(connectionID: String) async throws -> PlaidHostedLinkStatus {
        try await get(
            "api/plaid/hosted-link/\(connectionID)",
            as: PlaidHostedLinkStatusEnvelope.self
        ).data
    }

    func fetchFinanceOverview() async throws -> FinanceOverview {
        try await get("api/plaid/overview", as: FinanceOverviewEnvelope.self).data
    }

    /// Pulls any transaction delta already available from Plaid, then returns
    /// the same normalized overview used by the Finance screen.
    func syncPlaidTransactions() async throws -> FinanceOverview {
        struct Payload: Encodable {}
        return try await post(
            "api/plaid/transactions/sync",
            body: Payload(),
            as: FinanceOverviewEnvelope.self
        ).data
    }

    func disconnectPlaidItem(_ itemID: String) async throws -> Bool {
        try await delete(
            "api/plaid/items/\(itemID)",
            as: FinanceDisconnectEnvelope.self
        ).removed
    }

    // MARK: Income (provider-neutral Finance domain)

    /// Returns deterministic Income aggregates computed from every normalized
    /// transaction stored for the signed-in user. The local date prevents a UTC
    /// server boundary from putting a late-night deposit in the wrong month.
    func fetchIncomeOverview(asOfDate: String, timeZone: String) async throws -> IncomeOverview {
        struct Payload: Encodable {
            let asOfDate: String
            let timeZone: String
        }
        return try await post(
            "api/finance/income",
            body: Payload(asOfDate: asOfDate, timeZone: timeZone),
            as: IncomeOverviewEnvelope.self
        ).data
    }

    /// Persists an explicit user decision. The backend verifies transaction
    /// ownership and applies the resulting descriptor rule only within that
    /// same authenticated user's Finance partition.
    func classifyIncomeTransaction(
        _ transactionID: String,
        request: IncomeClassificationRequest
    ) async throws -> IncomeOverview {
        guard !transactionID.isEmpty else { throw APIError.badURL }
        return try await post(
            pathComponents: ["api", "finance", "income", "transactions", transactionID, "classification"],
            body: request,
            as: IncomeClassificationResponse.self
        ).data
    }

    // MARK: Helpers

    /// Attaches backend credentials. The admin password is stored in Keychain,
    /// never logged, and only sent over HTTPS.
    private func authorize(_ request: inout URLRequest) {
        if let password = KeychainStore.get(KeychainKeys.adminPassword), !password.isEmpty {
            request.setValue(password, forHTTPHeaderField: "x-admin-password")
        }
        if let idToken = KeychainStore.get(KeychainKeys.googleIDToken), !idToken.isEmpty {
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func url(for path: String) throws -> URL {
        guard let baseURL else {
            throw APIError.notConfigured("Remote tracker sync is not configured. Your jobs are still saved on this iPhone.")
        }
        return baseURL.appending(path: path)
    }

    private func url(forPathComponents components: [String]) throws -> URL {
        guard let baseURL, !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
            throw APIError.badURL
        }
        return components.reduce(baseURL) { partial, component in
            partial.appending(component: component, directoryHint: .notDirectory)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(status: http.statusCode, message: message)
        }
    }
}

/// The repository depends on this provider-neutral boundary rather than on a
/// particular aggregation vendor. Plaid remains the current adapter, while the
/// Income and overview UI consume only normalized Orbit models.
protocol FinanceDataProviding: AnyObject {
    var isConfigured: Bool { get }
    func createFinanceConnection() async throws -> PlaidHostedLinkLaunch
    func fetchFinanceConnectionStatus(connectionID: String) async throws -> PlaidHostedLinkStatus
    func syncFinanceOverview() async throws -> FinanceOverview
    func disconnectFinanceConnection(_ connectionID: String) async throws -> Bool
    func fetchIncomeOverview(asOfDate: String, timeZone: String) async throws -> IncomeOverview
    func classifyIncomeTransaction(
        _ transactionID: String,
        request: IncomeClassificationRequest
    ) async throws -> IncomeOverview
}

extension APIClient: FinanceDataProviding {
    func createFinanceConnection() async throws -> PlaidHostedLinkLaunch {
        try await createPlaidHostedLink()
    }

    func fetchFinanceConnectionStatus(connectionID: String) async throws -> PlaidHostedLinkStatus {
        try await fetchPlaidHostedLinkStatus(connectionID: connectionID)
    }

    func syncFinanceOverview() async throws -> FinanceOverview {
        try await syncPlaidTransactions()
    }

    func disconnectFinanceConnection(_ connectionID: String) async throws -> Bool {
        try await disconnectPlaidItem(connectionID)
    }
}

struct TrackerEnvelope: Decodable { let data: [JobApplicationDTO] }

/// Keychain account keys, centralized so nothing sensitive is scattered.
enum KeychainKeys {
    static let adminPassword = "orbit.adminPassword"
    static let googleIDToken = "orbit.google.idToken"
    static let googleAccessToken = "orbit.google.accessToken"
    static let openAIKey = "orbit.openai.apiKey"
}

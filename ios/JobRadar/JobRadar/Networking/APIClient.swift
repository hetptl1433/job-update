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

/// Thin async HTTP client for our backend. All AI and (eventually) Gmail
/// classification requests flow through here — the app never talks to OpenAI
/// directly and holds no OpenAI key.
final class APIClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
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

    private func send<Response: Decodable>(
        path: String, method: String, body: Data?, as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
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
        var request = URLRequest(url: baseURL.appending(path: "api/tracker"))
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

struct TrackerEnvelope: Decodable { let data: [JobApplicationDTO] }

/// Keychain account keys, centralized so nothing sensitive is scattered.
enum KeychainKeys {
    static let adminPassword = "orbit.adminPassword"
    static let googleIDToken = "orbit.google.idToken"
    static let googleAccessToken = "orbit.google.accessToken"
}

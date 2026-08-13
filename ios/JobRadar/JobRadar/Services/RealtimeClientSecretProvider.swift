import Foundation

/// Mints short-lived Realtime credentials using the OpenAI API key the owner
/// explicitly supplied. The returned credential is safe to hand to the live
/// voice client (including the paired Watch); the long-lived key is not.
struct RealtimeClientSecretProvider {
    private let apiKey: String
    private let safetyIdentifier: String?
    private let session: URLSession

    /// `safetyIdentifier`, when supplied, must already be a stable,
    /// privacy-preserving hash. Never pass an email address or raw user ID.
    init(
        apiKey: String,
        safetyIdentifier: String? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.safetyIdentifier = safetyIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func mintCredential(
        model: String = AppConfig.openAIRealtimeModel,
        instructions: String
    ) async throws -> RealtimeClientCredential {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw RealtimeClientSecretProviderError.missingAPIKey
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw RealtimeClientSecretProviderError.invalidModel
        }

        let payload: [String: Any] = [
            "expires_after": [
                "anchor": "created_at",
                "seconds": 600
            ],
            "session": RealtimeSessionConfigurationPayload.make(
                model: trimmedModel,
                instructions: instructions
            )
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw RealtimeClientSecretProviderError.encoding
        }

        var request = URLRequest(
            url: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        if let safetyIdentifier, !safetyIdentifier.isEmpty {
            request.setValue(safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RealtimeClientSecretProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RealtimeClientSecretProviderError.noHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.openAIMessage(in: data)
            switch http.statusCode {
            case 400:
                throw RealtimeClientSecretProviderError.badRequest(message)
            case 401:
                throw RealtimeClientSecretProviderError.unauthorized
            case 403:
                throw RealtimeClientSecretProviderError.forbidden(message)
            case 429:
                throw RealtimeClientSecretProviderError.rateLimited(message)
            default:
                throw RealtimeClientSecretProviderError.server(
                    status: http.statusCode,
                    message: message
                )
            }
        }

        let decoded: SecretResponse
        do {
            decoded = try JSONDecoder().decode(SecretResponse.self, from: data)
        } catch {
            throw RealtimeClientSecretProviderError.invalidResponse
        }
        let value = decoded.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw RealtimeClientSecretProviderError.invalidResponse
        }
        return RealtimeClientCredential(
            value: value,
            expiresAt: decoded.expiresAt.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func openAIMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorEnvelope.self, from: data)).flatMap {
            $0.error?.message ?? $0.message
        }
    }

    private struct SecretResponse: Decodable {
        let value: String
        let expiresAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
        }
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorBody?
        let message: String?

        struct ErrorBody: Decodable {
            let message: String?
        }
    }
}

enum RealtimeClientSecretProviderError: LocalizedError {
    case missingAPIKey
    case invalidModel
    case encoding
    case network(String)
    case noHTTPResponse
    case badRequest(String?)
    case unauthorized
    case forbidden(String?)
    case rateLimited(String?)
    case server(status: Int, message: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Connect OpenAI in Settings before starting live voice."
        case .invalidModel:
            return "No OpenAI Realtime model is configured."
        case .encoding:
            return "Orbit couldn't prepare the live voice request."
        case let .network(message):
            return "Orbit couldn't reach OpenAI: \(message)"
        case .noHTTPResponse:
            return "OpenAI did not return a valid network response."
        case let .badRequest(message):
            return message ?? "OpenAI rejected the live voice configuration."
        case .unauthorized:
            return "That OpenAI API key was not accepted."
        case let .forbidden(message):
            return message ?? "This OpenAI project does not have access to live voice."
        case let .rateLimited(message):
            return message ?? "OpenAI's rate or usage limit was reached. Try again shortly."
        case let .server(status, message):
            return message ?? "OpenAI couldn't create a live voice credential (HTTP \(status))."
        case .invalidResponse:
            return "OpenAI returned an unreadable live voice credential."
        }
    }
}

import Foundation

/// Small Responses API client used by the personal-development build.
///
/// The key is supplied at runtime and never compiled into the app or logged.
/// A public/App Store build should proxy these calls through a backend because
/// secrets embedded in any mobile application can ultimately be extracted.
struct OpenAIClient {
    enum ReasoningEffort: String {
        case low, medium, high
    }

    struct JSONSchema {
        let name: String
        let value: [String: Any]
    }

    let apiKey: String
    var model: String = AppConfig.openAIModel
    var session: URLSession = .shared

    private struct Response: Decodable {
        let status: String?
        let output: [OutputItem]
        let error: ErrorBody?
        let incompleteDetails: IncompleteDetails?

        enum CodingKeys: String, CodingKey {
            case status, output, error
            case incompleteDetails = "incomplete_details"
        }

        struct OutputItem: Decodable {
            let type: String
            let content: [Content]?
        }

        struct Content: Decodable {
            let type: String
            let text: String?
            let refusal: String?
        }

        struct ErrorBody: Decodable { let message: String }
        struct IncompleteDetails: Decodable { let reason: String? }
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorBody
        struct ErrorBody: Decodable { let message: String }
    }

    /// Confirms that the supplied credential can authenticate without sending
    /// any user data or consuming model output tokens.
    func validateCredential() async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    /// Generate text, optionally constrained to a strict JSON schema.
    func complete(
        system: String,
        user: String,
        schema: JSONSchema? = nil,
        maxOutputTokens: Int = 4_000,
        reasoningEffort: ReasoningEffort? = nil
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.notConfigured("No OpenAI API key is connected.")
        }

        let payload = requestPayload(
            system: system,
            user: user,
            schema: schema,
            maxOutputTokens: maxOutputTokens,
            reasoningEffort: reasoningEffort
        )

        guard JSONSerialization.isValidJSONObject(payload) else {
            throw APIError.decoding("The AI request could not be encoded.")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding("OpenAI returned an unreadable response: \(error.localizedDescription)")
        }

        if let message = decoded.error?.message {
            throw APIError.server(status: -1, message: message)
        }
        if decoded.status == "incomplete" {
            throw APIError.server(
                status: -1,
                message: "The AI response was incomplete (\(decoded.incompleteDetails?.reason ?? "unknown reason")). Try syncing fewer messages."
            )
        }

        var textParts: [String] = []
        for item in decoded.output where item.type == "message" {
            for content in item.content ?? [] {
                if content.type == "refusal", let refusal = content.refusal, !refusal.isEmpty {
                    throw APIError.server(status: -1, message: refusal)
                }
                if content.type == "output_text", let text = content.text, !text.isEmpty {
                    textParts.append(text)
                }
            }
        }
        let result = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw APIError.decoding("OpenAI returned no text.")
        }
        return result
    }

    /// Kept internal so unit tests can verify model routing and Structured
    /// Outputs without sending a network request.
    func requestPayload(
        system: String,
        user: String,
        schema: JSONSchema? = nil,
        maxOutputTokens: Int = 4_000,
        reasoningEffort: ReasoningEffort? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "instructions": system,
            "input": user,
            "store": false,
            "max_output_tokens": maxOutputTokens
        ]
        if let schema {
            payload["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": schema.name,
                    "strict": true,
                    "schema": schema.value
                ]
            ]
        }
        if let reasoningEffort, supportsReasoningEffort {
            payload["reasoning"] = ["effort": reasoningEffort.rawValue]
        }
        return payload
    }

    private var supportsReasoningEffort: Bool {
        model == "gpt-5.6" || model.hasPrefix("gpt-5.6-")
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "No HTTP response was received.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            switch http.statusCode {
            case 401:
                throw APIError.server(status: 401, message: "That OpenAI API key was not accepted.")
            case 429:
                throw APIError.server(status: 429, message: serverMessage ?? "OpenAI rate limit or usage limit reached. Try again shortly.")
            default:
                throw APIError.server(status: http.statusCode, message: serverMessage)
            }
        }
    }
}

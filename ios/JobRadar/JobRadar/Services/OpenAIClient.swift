import Foundation

/// Minimal direct client for the OpenAI Chat Completions API.
///
/// The API key is supplied by the user at runtime and stored in the Keychain —
/// it is never compiled into the app, committed, or logged. Used only when the
/// user connects ChatGPT with their own key.
struct OpenAIClient {
    let apiKey: String
    var model: String = "gpt-4o"

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct Response: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorBody
        struct ErrorBody: Decodable { let message: String }
    }

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.notConfigured("No OpenAI key.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server(status: -1, message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw APIError.server(status: http.statusCode, message: message)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}

import Foundation

/// The AI intelligence layer as seen by the app.
///
/// When the user connects ChatGPT with their own key, the assistant calls
/// OpenAI directly with a compact, structured context (jobs, inbox, connections)
/// — it does not dump raw data. The key is user-supplied and Keychain-stored;
/// nothing sensitive is compiled into the app. This can later be swapped for a
/// backend-brokered implementation without changing the UI.
protocol AssistantService {
    var isConnected: Bool { get }
    func answer(_ prompt: String, context: AssistantContext) async throws -> String
}

/// Compact, already-summarized context handed to the model.
struct AssistantContext {
    var userName: String
    var lines: [String]

    var text: String {
        lines.isEmpty ? "(no connected data yet)" : lines.joined(separator: "\n")
    }
}

/// Live assistant backed by the user's own OpenAI key.
struct LiveAssistantService: AssistantService {
    let api: APIClient

    var isConnected: Bool {
        !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    func answer(_ prompt: String, context: AssistantContext) async throws -> String {
        guard let key = KeychainStore.get(KeychainKeys.openAIKey), !key.isEmpty else {
            throw APIError.notConfigured("Connect ChatGPT in Settings to use the assistant.")
        }
        let client = OpenAIClient(apiKey: key)
        return try await client.complete(system: Self.systemPrompt(context), user: prompt)
    }

    private static func systemPrompt(_ context: AssistantContext) -> String {
        """
        You are Orbit, \(context.userName)'s personal command-center assistant. \
        You help with their email, job applications, calendar, tasks and health. \
        Answer concisely and practically. Use ONLY the context below when the \
        question is about the user's data; if the answer isn't in the context, \
        say what's missing or what to connect. Do not invent emails, jobs or events.

        USER CONTEXT
        \(context.text)
        """
    }
}

/// A single line in the Assistant conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
}

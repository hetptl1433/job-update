import Foundation

/// In-memory, AI-filtered unified inbox. Provider-specific payloads never reach
/// SwiftUI and raw message bodies are intentionally not retained here.
@MainActor
final class EmailRepository: ObservableObject {
    @Published private(set) var state: LoadState<[InboxMessage]> = .disconnected
    private(set) var connected = false

    var needsInitialLoad: Bool {
        guard connected else { return false }
        if case .idle = state { return true }
        return false
    }

    func markConnected(_ value: Bool) {
        connected = value
        if value {
            // A restored account is connected even though this process has not
            // fetched its in-memory Inbox data yet.
            if case .disconnected = state { state = .idle }
        } else {
            state = .disconnected
        }
    }

    func beginLoading() { state = .loading }

    func setMessages(_ messages: [InboxMessage]) {
        connected = true
        state = messages.isEmpty ? .empty : .loaded(messages)
    }

    func setFailure(_ message: String) {
        state = .failed(message)
    }

    /// Pull-to-refresh is opportunistic. Clear an old transient error while
    /// preserving loaded data; explicit Sync can still present the real error.
    func clearTransientFailure() {
        if case .failed = state { state = connected ? .empty : .disconnected }
    }

    func messages(in section: InboxSection) -> [InboxMessage] {
        (state.value ?? []).filter { $0.section == section }
    }
}

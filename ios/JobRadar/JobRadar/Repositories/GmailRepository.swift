import Foundation

/// AI-filtered unified inbox. Provider-specific payloads and raw message bodies
/// are never retained; the compact classified result is protected on disk so a
/// cold launch can render immediately while providers refresh.
@MainActor
final class EmailRepository: ObservableObject {
    @Published private(set) var state: LoadState<[InboxMessage]> = .idle
    @Published private(set) var refreshError: String?
    @Published private(set) var snapshotDate: Date?

    private(set) var connected = false
    private var didAttemptInitialLoad = false
    private let snapshotStore: ProtectedSnapshotStore<[InboxMessage]>

    init(snapshotStore: ProtectedSnapshotStore<[InboxMessage]>? = nil) {
        self.snapshotStore = snapshotStore
            ?? ProtectedSnapshotStore(filename: "orbit-inbox-v1.json")
        if let snapshot = self.snapshotStore.load(ownerID: UserSession.restore()?.userID) {
            state = snapshot.value.isEmpty ? .empty : .loaded(snapshot.value)
            snapshotDate = snapshot.savedAt
        }
    }

    var needsInitialLoad: Bool {
        connected && !didAttemptInitialLoad
    }

    func markConnected(_ value: Bool) {
        connected = value
        if value {
            // A restored account is connected even though this process has not
            // refreshed its Inbox data yet. A protected snapshot may already
            // be visible while that refresh runs.
            if case .disconnected = state { state = .idle }
        } else {
            state = .disconnected
            refreshError = nil
            snapshotDate = nil
            didAttemptInitialLoad = false
            snapshotStore.remove()
        }
    }

    /// Existing results remain visible during a refresh. A blocking loading
    /// state is needed only when there is no snapshot to show yet.
    func beginLoading() {
        didAttemptInitialLoad = true
        refreshError = nil
        if state.value == nil { state = .loading }
    }

    func setMessages(_ messages: [InboxMessage]) {
        connected = true
        didAttemptInitialLoad = true
        refreshError = nil
        snapshotDate = .now
        state = messages.isEmpty ? .empty : .loaded(messages)
        snapshotStore.save(messages, ownerID: UserSession.restore()?.userID)
    }

    func setFailure(_ message: String) {
        didAttemptInitialLoad = true
        if state.value != nil {
            refreshError = message
        } else {
            state = .failed(message)
        }
    }

    /// Pull-to-refresh is opportunistic. Clear an old transient error while
    /// preserving loaded data; explicit Sync can still present the real error.
    func clearTransientFailure() {
        refreshError = nil
        if case .failed = state { state = connected ? .idle : .disconnected }
    }

    func messages(in section: InboxSection) -> [InboxMessage] {
        (state.value ?? []).filter { $0.section == section }
    }
}

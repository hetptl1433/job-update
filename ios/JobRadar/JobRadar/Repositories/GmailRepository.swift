import Foundation

enum EmailSuggestionDecision: String, Codable, Equatable {
    case accepted
    case dismissed
}

struct EmailAccountScanState: Codable, Equatable {
    var lastSuccessfulScan: Date?
    var processedMessageDates: [String: Date] = [:]
}

struct EmailScanHistorySnapshot: Codable, Equatable {
    var schemaVersion = 1
    var analysisVersion = 1
    var accounts: [String: EmailAccountScanState] = [:]
    var jobDecisions: [String: EmailSuggestionDecision] = [:]
    var taskDecisions: [String: EmailSuggestionDecision] = [:]
    var pendingJobUpdates: [DetectedJobUpdate] = []
}

/// Remembers what was successfully analyzed and how the owner handled derived
/// suggestions. Only provider IDs, dates, and compact app-facing results are
/// retained; raw email bodies never touch disk.
@MainActor
final class EmailScanHistoryStore {
    private(set) var snapshot = EmailScanHistorySnapshot()
    private(set) var ownerID: String?
    private(set) var requiresFullRescan = false
    private var fullRescanRemainingAccounts = Set<String>()

    private let store: ProtectedSnapshotStore<EmailScanHistorySnapshot>
    private let overlap: TimeInterval
    private let retention: TimeInterval

    init(
        directory: URL? = nil,
        overlap: TimeInterval = 10 * 60,
        retention: TimeInterval = 90 * 24 * 60 * 60
    ) {
        let location = directory ?? Self.applicationSupportDirectory()
        store = ProtectedSnapshotStore(
            filename: "orbit-email-scan-history-v1.json",
            directory: location
        )
        self.overlap = overlap
        self.retention = retention
    }

    var pendingJobUpdates: [DetectedJobUpdate] { snapshot.pendingJobUpdates }
    var resolvedTaskMessageIDs: Set<String> { Set(snapshot.taskDecisions.keys) }
    var hasProcessedMessages: Bool {
        snapshot.accounts.values.contains {
            $0.lastSuccessfulScan != nil || !$0.processedMessageDates.isEmpty
        }
    }

    func load(ownerID: String?) {
        guard let ownerID, !ownerID.isEmpty else {
            unload()
            return
        }
        self.ownerID = ownerID
        snapshot = store.load(ownerID: ownerID)?.value ?? EmailScanHistorySnapshot()
        requiresFullRescan = false
        fullRescanRemainingAccounts = []
        prune(at: .now)
    }

    func unload() {
        ownerID = nil
        snapshot = EmailScanHistorySnapshot()
        requiresFullRescan = false
        fullRescanRemainingAccounts = []
    }

    @discardableResult
    func eraseOwnerData() -> Bool {
        guard store.remove() else {
            // Stop this process from exposing or mutating the owner's state even
            // when disk cleanup needs another attempt.
            unload()
            return false
        }
        unload()
        return true
    }

    func receivedAfter(for accountID: String) -> Date? {
        guard !requiresFullRescan else { return nil }
        return snapshot.accounts[accountID]?.lastSuccessfulScan?
            .addingTimeInterval(-overlap)
    }

    func processedMessageIDs(for accountID: String) -> Set<String> {
        guard let dates = snapshot.accounts[accountID]?.processedMessageDates else { return [] }
        return Set(dates.keys)
    }

    /// Records successfully analyzed IDs. A nil `cursorDate` intentionally
    /// leaves the cursor in place while another provider batch is waiting.
    @discardableResult
    func recordSuccessfulAnalysis(
        accountID: String,
        messages: [EmailMessage],
        jobUpdates: [DetectedJobUpdate],
        cursorDate: Date? = .now
    ) -> Bool {
        let previous = snapshot
        var account = snapshot.accounts[accountID] ?? EmailAccountScanState()
        for message in messages {
            account.processedMessageDates[message.id] = message.receivedDate
        }
        if let cursorDate { account.lastSuccessfulScan = cursorDate }
        snapshot.accounts[accountID] = account

        var pendingByKey = Dictionary(
            snapshot.pendingJobUpdates.map { ($0.decisionKey, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        for update in jobUpdates where snapshot.jobDecisions[update.decisionKey] == nil {
            pendingByKey[update.decisionKey] = update
        }
        snapshot.pendingJobUpdates = pendingByKey.values.sorted {
            ($0.sourceDate ?? .distantPast) > ($1.sourceDate ?? .distantPast)
        }
        prune(at: cursorDate ?? .now)
        guard persist() else {
            snapshot = previous
            return false
        }
        if cursorDate != nil { finishFullRescanIfNeeded(accountID: accountID) }
        return true
    }

    /// A successful provider query with no unseen messages still advances the
    /// cursor; otherwise every foreground refresh repeats the same overlap.
    @discardableResult
    func recordSuccessfulEmptyScan(accountID: String, cursorDate: Date = .now) -> Bool {
        let previous = snapshot
        var account = snapshot.accounts[accountID] ?? EmailAccountScanState()
        account.lastSuccessfulScan = cursorDate
        snapshot.accounts[accountID] = account
        prune(at: cursorDate)
        guard persist() else {
            snapshot = previous
            return false
        }
        finishFullRescanIfNeeded(accountID: accountID)
        return true
    }

    @discardableResult
    func recordJobDecision(
        _ decision: EmailSuggestionDecision,
        for update: DetectedJobUpdate
    ) -> Bool {
        let previous = snapshot
        snapshot.jobDecisions[update.decisionKey] = decision
        snapshot.pendingJobUpdates.removeAll { $0.decisionKey == update.decisionKey }
        guard persist() else {
            snapshot = previous
            return false
        }
        return true
    }

    @discardableResult
    func recordTaskDecision(
        _ decision: EmailSuggestionDecision,
        sourceMessageID: String?
    ) -> Bool {
        guard let sourceMessageID, !sourceMessageID.isEmpty else { return false }
        let previous = snapshot
        snapshot.taskDecisions[sourceMessageID] = decision
        guard persist() else {
            snapshot = previous
            return false
        }
        return true
    }

    @discardableResult
    func removeAccount(_ account: EmailAccount) -> Bool {
        let previous = snapshot
        let previousRequiresFullRescan = requiresFullRescan
        let previousRemainingAccounts = fullRescanRemainingAccounts
        snapshot.accounts.removeValue(forKey: account.id)
        fullRescanRemainingAccounts.remove(account.id)
        if fullRescanRemainingAccounts.isEmpty { requiresFullRescan = false }
        snapshot.pendingJobUpdates.removeAll {
            if let sourceID = $0.sourceMessageID {
                return sourceID.hasPrefix("\(account.id):")
            }
            // Legacy entries without a source ID fall back to mailbox identity.
            return $0.sourceProvider == account.provider
                && $0.sourceMailbox.caseInsensitiveCompare(account.email) == .orderedSame
        }
        // Resolved decisions remain keyed by immutable provider message IDs so
        // reconnecting the same mailbox cannot resurrect dismissed tasks.
        guard persist() else {
            snapshot = previous
            requiresFullRescan = previousRequiresFullRescan
            fullRescanRemainingAccounts = previousRemainingAccounts
            return false
        }
        return true
    }

    /// If the independently stored Inbox snapshot is missing or corrupt, force
    /// a safe rebuild rather than trusting processed IDs that could hide data.
    @discardableResult
    func resetProcessingStateKeepingDecisions() -> Bool {
        requiresFullRescan = true
        fullRescanRemainingAccounts = Set(snapshot.accounts.keys)
        guard !snapshot.accounts.isEmpty else {
            requiresFullRescan = false
            return true
        }
        snapshot.accounts = [:]
        guard persist() else {
            // Keep the cleared in-memory working copy. It hides the stale disk
            // baseline while allowing newly analyzed IDs to accumulate, so a
            // >40-message rebuild drains instead of repeating its first page.
            return false
        }
        requiresFullRescan = false
        fullRescanRemainingAccounts = []
        return true
    }

    private func finishFullRescanIfNeeded(accountID: String) {
        guard requiresFullRescan else { return }
        fullRescanRemainingAccounts.remove(accountID)
        if fullRescanRemainingAccounts.isEmpty { requiresFullRescan = false }
    }

    private func prune(at now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        for accountID in snapshot.accounts.keys {
            guard var account = snapshot.accounts[accountID] else { continue }
            account.processedMessageDates = account.processedMessageDates.filter { $0.value >= cutoff }
            snapshot.accounts[accountID] = account
        }
        snapshot.pendingJobUpdates.removeAll {
            guard let date = $0.sourceDate else { return false }
            return date < cutoff
        }
        // Job decisions are intentionally retained: their stable keys are tiny,
        // and keeping them prevents an old provider message from resurfacing if
        // a mailbox later returns a wider historical window.
    }

    private func persist() -> Bool {
        store.save(snapshot, ownerID: ownerID)
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orbit", isDirectory: true)
    }
}

/// AI-filtered unified inbox. Provider-specific payloads and raw message bodies
/// are never retained; the compact classified result is protected on disk so a
/// cold launch can render immediately while providers refresh.
@MainActor
final class EmailRepository: ObservableObject {
    @Published private(set) var state: LoadState<[InboxMessage]> = .idle
    @Published private(set) var refreshError: String?
    @Published private(set) var snapshotDate: Date?

    private(set) var connected = false
    private(set) var hasStoredSnapshot = false
    private var didAttemptInitialLoad = false
    private let snapshotStore: ProtectedSnapshotStore<[InboxMessage]>

    init(snapshotStore: ProtectedSnapshotStore<[InboxMessage]>? = nil) {
        self.snapshotStore = snapshotStore
            ?? ProtectedSnapshotStore(
                filename: "orbit-inbox-v2.json",
                directory: Self.applicationSupportDirectory()
            )
        if let snapshot = self.snapshotStore.load(ownerID: UserSession.restore()?.userID) {
            state = snapshot.value.isEmpty ? .empty : .loaded(snapshot.value)
            snapshotDate = snapshot.savedAt
            hasStoredSnapshot = true
        }
    }

    var needsInitialLoad: Bool {
        connected && !didAttemptInitialLoad
    }

    var allMessages: [InboxMessage] { state.value ?? [] }

    @discardableResult
    func markConnected(_ value: Bool) -> Bool {
        connected = value
        if value {
            // A restored account is connected even though this process has not
            // refreshed its Inbox data yet. A protected snapshot may already
            // be visible while that refresh runs.
            if case .disconnected = state { state = .idle }
            return true
        } else {
            state = .disconnected
            refreshError = nil
            snapshotDate = nil
            hasStoredSnapshot = false
            didAttemptInitialLoad = false
            return snapshotStore.remove()
        }
    }

    @discardableResult
    func eraseStoredSnapshot() -> Bool {
        guard snapshotStore.remove() else { return false }
        hasStoredSnapshot = false
        return true
    }

    /// Existing results remain visible during a refresh. A blocking loading
    /// state is needed only when there is no snapshot to show yet.
    func beginLoading() {
        didAttemptInitialLoad = true
        refreshError = nil
        if state.value == nil { state = .loading }
    }

    @discardableResult
    func setMessages(_ messages: [InboxMessage]) -> Bool {
        let previousState = state
        let previousRefreshError = refreshError
        let previousSnapshotDate = snapshotDate
        let previousConnected = connected
        let previousAttempt = didAttemptInitialLoad
        let normalized = Dictionary(
            messages.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.receivedAt > $1.receivedAt }
        connected = true
        didAttemptInitialLoad = true
        refreshError = nil
        snapshotDate = .now
        state = normalized.isEmpty ? .empty : .loaded(normalized)
        let saved = snapshotStore.save(normalized, ownerID: UserSession.restore()?.userID)
        if saved {
            hasStoredSnapshot = true
            return true
        }
        state = previousState
        refreshError = previousRefreshError
        snapshotDate = previousSnapshotDate
        connected = previousConnected
        didAttemptInitialLoad = previousAttempt
        return false
    }

    /// Incremental scans update only messages returned by the AI and keep the
    /// existing important Inbox instead of clearing it when there is no new mail.
    @discardableResult
    func mergeMessages(_ messages: [InboxMessage], now: Date = .now) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: now)
            ?? now.addingTimeInterval(-60 * 24 * 60 * 60)
        var byID = Dictionary(
            allMessages.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        for message in messages { byID[message.id] = message }
        return setMessages(byID.values.filter { $0.receivedAt >= cutoff })
    }

    @discardableResult
    func finishRefreshWithoutChanges(now: Date = .now) -> Bool {
        connected = true
        didAttemptInitialLoad = true
        refreshError = nil
        // Also prune entries that crossed the 60-day boundary since the last
        // important result; an empty provider scan must not freeze stale rows.
        return mergeMessages([], now: now)
    }

    @discardableResult
    func removeMessages(for account: EmailAccount) -> Bool {
        let filtered = allMessages.filter { $0.accountID != account.id }
        guard setMessages(filtered) else {
            // Credential removal is authoritative even if local disk cleanup
            // needs a retry; never keep the disconnected mailbox visible.
            connected = true
            didAttemptInitialLoad = true
            state = filtered.isEmpty ? .empty : .loaded(filtered)
            return false
        }
        return true
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

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orbit", isDirectory: true)
    }
}

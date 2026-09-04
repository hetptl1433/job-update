import Combine
import Foundation

/// Main-actor state for the one-glance Finance screen. Every Plaid request is
/// routed through Orbit's authenticated backend; this object never handles a
/// Plaid secret or Item access token.
@MainActor
final class FinanceRepository: ObservableObject {
    @Published private(set) var state: LoadState<FinanceOverview> = .idle
    @Published private(set) var incomeState: LoadState<IncomeOverview> = .disconnected
    @Published private(set) var isConnecting = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var hostedLinkNotice: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var snapshotDate: Date?
    @Published private(set) var isSmartCategorizing = false
    @Published private(set) var smartCategorizationMessage: String?

    private let api: any FinanceDataProviding
    private let auth: AuthenticationManager
    private let defaults: UserDefaults
    private let snapshotStore: ProtectedSnapshotStore<FinanceOverview>
    private let categoryMemoryStore: ProtectedSnapshotStore<FinanceCategoryMemory>
    private var categoryMemory: FinanceCategoryMemory
    private var lastNetworkRefreshAt: Date?
    private var smartCategorizationTask: Task<Void, Never>?

    private static let pendingHostedLinkKey = "orbit.finance.pendingHostedLink"
    private static let automaticRefreshInterval: TimeInterval = 120

    init(
        api: any FinanceDataProviding,
        auth: AuthenticationManager,
        defaults: UserDefaults = .standard,
        snapshotStore: ProtectedSnapshotStore<FinanceOverview>? = nil,
        categoryMemoryStore: ProtectedSnapshotStore<FinanceCategoryMemory>? = nil
    ) {
        self.api = api
        self.auth = auth
        self.defaults = defaults
        self.snapshotStore = snapshotStore
            ?? ProtectedSnapshotStore(filename: "orbit-finance-overview-v1.json")
        self.categoryMemoryStore = categoryMemoryStore
            ?? ProtectedSnapshotStore(filename: "orbit-finance-category-memory-v1.json")

        let ownerID = UserSession.restore()?.userID
        let savedMemory = self.categoryMemoryStore.load(ownerID: ownerID)?.value
        self.categoryMemory = savedMemory?.version == FinanceCategoryMemory.currentVersion
            ? savedMemory!
            : FinanceCategoryMemory()

        if let snapshot = self.snapshotStore.load(ownerID: ownerID) {
            let categorized = self.categoryMemory.applying(to: snapshot.value)
            state = categorized.accounts.isEmpty ? .empty : .loaded(categorized)
            snapshotDate = snapshot.savedAt
            lastNetworkRefreshAt = snapshot.savedAt
        } else if !api.isConfigured {
            state = .disconnected
        }
    }

    var isBackendConfigured: Bool { api.isConfigured }
    var overview: FinanceOverview? { state.value }
    var incomeOverview: IncomeOverview? { incomeState.value }
    var isConnected: Bool { !(overview?.accounts.isEmpty ?? true) }
    var hasPendingHostedLink: Bool { pendingHostedLinkID != nil }
    var learnedMerchantCategoryCount: Int { categoryMemory.learnedRuleCount }

    func load(showLoading: Bool = true, forceRefresh: Bool = false) async {
        guard api.isConfigured else {
            state = .disconnected
            incomeState = .disconnected
            return
        }
        guard !isRefreshing else { return }
        if !forceRefresh,
           let lastNetworkRefreshAt,
           Date().timeIntervalSince(lastNetworkRefreshAt) < Self.automaticRefreshInterval {
            if isConnected, incomeState.value == nil {
                await loadIncome(showLoading: false)
            }
            organizeUnknownTransactions()
            return
        }

        let stateBeforeRefresh = state
        let incomeStateBeforeRefresh = incomeState
        if showLoading, state.value == nil { state = .loading }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            await refreshBackendIdentity()

            // A stored backend read model is much faster than waiting for every
            // Plaid Item to sync. Use it to paint the screen first when this
            // device has no local snapshot, then refresh accounts in place.
            if stateBeforeRefresh.value == nil {
                if let overview = try? await api.fetchFinanceOverview() {
                    apply(overview)
                }
            }

            let overview = try await api.syncFinanceOverview()
            apply(overview)
            lastNetworkRefreshAt = .now
            if !overview.accounts.isEmpty {
                await loadIncome(showLoading: incomeState.value == nil)
            }
        } catch is CancellationError {
            if case .loading = state { state = stateBeforeRefresh }
            if case .loading = incomeState { incomeState = incomeStateBeforeRefresh }
        } catch {
            if state.value != nil {
                refreshError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
                incomeState = .failed(error.localizedDescription)
            }
        }
    }

    /// Income has an independent state so an older/unavailable Income endpoint
    /// cannot erase an otherwise valid balances-and-activity overview.
    func loadIncome(showLoading: Bool = true) async {
        guard api.isConfigured else {
            incomeState = .disconnected
            return
        }
        guard isConnected else {
            incomeState = state == .disconnected ? .disconnected : .empty
            return
        }
        let previousState = incomeState
        if showLoading, incomeState.value == nil { incomeState = .loading }

        do {
            await refreshBackendIdentity()
            let overview = try await api.fetchIncomeOverview(
                asOfDate: Self.localDateString(),
                timeZone: TimeZone.current.identifier
            )
            incomeState = overview.summaries.isEmpty ? .empty : .loaded(overview)
        } catch is CancellationError {
            // Never strand the page in a loading state after navigation or
            // background cancellation.
            incomeState = previousState
        } catch {
            incomeState = .failed(error.localizedDescription)
        }
    }

    func classifyIncomeTransaction(
        id: String,
        as classification: IncomeClassification,
        sourceName: String? = nil,
        sourceType: IncomeType? = nil
    ) async throws {
        guard classification == .income || classification == .notIncome else {
            throw APIError.server(status: 400, message: "Choose Income or Not income before saving.")
        }
        let trimmedName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if classification == .income, trimmedName?.isEmpty != false {
            throw APIError.server(status: 400, message: "Enter a name for this income source.")
        }

        await refreshBackendIdentity()
        let overview = try await api.classifyIncomeTransaction(
            id,
            request: IncomeClassificationRequest(
                classification: classification,
                sourceName: classification == .income ? trimmedName : nil,
                type: classification == .income ? sourceType : nil,
                asOfDate: Self.localDateString(),
                timeZone: TimeZone.current.identifier
            )
        )
        incomeState = overview.summaries.isEmpty ? .empty : .loaded(overview)
    }

    /// Creates a short-lived Plaid webpage owned by the backend. The only value
    /// persisted on-device is Orbit's random connection ID so a callback can be
    /// resumed after the app has been suspended or relaunched.
    func createHostedLink() async throws -> PlaidHostedLinkLaunch {
        guard api.isConfigured else {
            throw APIError.notConfigured(
                "Finance needs Orbit's secure backend URL before a bank can be connected."
            )
        }
        isConnecting = true
        hostedLinkNotice = nil
        defer { isConnecting = false }
        await refreshBackendIdentity()
        let launch = try await api.createFinanceConnection()
        pendingHostedLinkID = launch.connectionID
        return launch
    }

    /// Resolves the callback/webhook race with a short bounded poll. Plaid's
    /// signed webhook performs the token exchange on Orbit's backend, so this
    /// app only waits for a safe status and then reloads the normalized data.
    func resumeHostedLinkIfNeeded() async {
        guard let connectionID = pendingHostedLinkID else {
            await load(showLoading: false)
            return
        }
        guard !isConnecting else { return }

        isConnecting = true
        hostedLinkNotice = nil
        defer { isConnecting = false }
        await refreshBackendIdentity()

        do {
            for attempt in 0..<10 {
                let result = try await api.fetchFinanceConnectionStatus(connectionID: connectionID)
                switch result.status {
                case .complete:
                    pendingHostedLinkID = nil
                    lastNetworkRefreshAt = nil
                    await load(showLoading: false, forceRefresh: true)
                    return
                case .exited:
                    pendingHostedLinkID = nil
                    hostedLinkNotice = "Bank connection was canceled. No account was added."
                    await load(showLoading: false)
                    return
                case .failed:
                    pendingHostedLinkID = nil
                    hostedLinkNotice = result.message ?? "The bank connection could not be completed. Please try again."
                    await load(showLoading: false)
                    return
                case .expired:
                    pendingHostedLinkID = nil
                    hostedLinkNotice = "That secure bank connection expired. Start a new connection to try again."
                    await load(showLoading: false)
                    return
                case .pending, .processing:
                    if attempt < 9 {
                        try await Task.sleep(for: .seconds(1))
                    }
                }
            }

            // Keep the ID so a later foreground/refresh can check again. The
            // webhook may still be completing, and that is not a user error.
            await load(showLoading: false, forceRefresh: true)
        } catch is CancellationError {
            // App moved back to the background; keep the pending ID for later.
        } catch {
            hostedLinkNotice = "Orbit is still waiting for the secure bank connection. Pull to refresh in a moment."
        }
    }

    func clearHostedLinkNotice() {
        hostedLinkNotice = nil
    }

    func clearRefreshError() {
        refreshError = nil
    }

    /// Starts a bounded background pass only for merchants still categorized
    /// as Other. Saved merchant rules are reused on every later sync.
    func organizeUnknownTransactions() {
        scheduleSmartCategorization(for: state.value)
    }

    func disconnect(itemID: String) async throws {
        await refreshBackendIdentity()
        _ = try await api.disconnectFinanceConnection(itemID)
        lastNetworkRefreshAt = nil
        await load(showLoading: false, forceRefresh: true)
    }

    func clear() {
        smartCategorizationTask?.cancel()
        smartCategorizationTask = nil
        state = .disconnected
        incomeState = .disconnected
        isConnecting = false
        isRefreshing = false
        hostedLinkNotice = nil
        refreshError = nil
        isSmartCategorizing = false
        smartCategorizationMessage = nil
        snapshotDate = nil
        lastNetworkRefreshAt = nil
        pendingHostedLinkID = nil
        snapshotStore.remove()
        categoryMemoryStore.remove()
        categoryMemory = FinanceCategoryMemory()
    }

    private func apply(_ overview: FinanceOverview) {
        let categorized = categoryMemory.applying(to: overview)
        state = categorized.accounts.isEmpty ? .empty : .loaded(categorized)
        incomeState = categorized.accounts.isEmpty ? .empty : incomeState
        snapshotDate = .now
        snapshotStore.save(categorized, ownerID: UserSession.restore()?.userID)
        scheduleSmartCategorization(for: categorized)
    }

    private func scheduleSmartCategorization(for overview: FinanceOverview?) {
        smartCategorizationTask?.cancel()
        smartCategorizationTask = nil
        guard let overview,
              let key = KeychainStore.get(KeychainKeys.openAIKey),
              !key.isEmpty else {
            isSmartCategorizing = false
            return
        }
        let samples = categoryMemory.unclassifiedSamples(in: overview)
        guard !samples.isEmpty else {
            isSmartCategorizing = false
            return
        }

        smartCategorizationTask = Task { [weak self] in
            guard let self else { return }
            await self.runSmartCategorization(samples: samples, apiKey: key)
        }
    }

    private func runSmartCategorization(
        samples: [FinanceMerchantSample],
        apiKey: String
    ) async {
        isSmartCategorizing = true
        smartCategorizationMessage = nil
        defer { isSmartCategorizing = false }
        do {
            let learnedRules = try await FinanceCategoryIntelligence(apiKey: apiKey).classify(samples)
            try Task.checkCancellation()
            guard !learnedRules.isEmpty else { return }

            var updatedMemory = categoryMemory
            updatedMemory.remember(learnedRules)
            let ownerID = UserSession.restore()?.userID
            guard categoryMemoryStore.save(updatedMemory, ownerID: ownerID) else {
                smartCategorizationMessage = "Smart categories could not be saved securely, so no transaction was changed."
                return
            }

            categoryMemory = updatedMemory
            if let current = state.value {
                let categorized = categoryMemory.applying(to: current)
                state = categorized.accounts.isEmpty ? .empty : .loaded(categorized)
                snapshotStore.save(categorized, ownerID: ownerID)
            }
            let count = learnedRules.count
            smartCategorizationMessage = "Learned \(count) merchant categor\(count == 1 ? "y" : "ies") for future transactions."
        } catch is CancellationError {
            // A newer bank sync superseded this batch.
        } catch {
            smartCategorizationMessage = "Smart categorization will retry later: \(error.localizedDescription)"
        }
    }

    private var pendingHostedLinkID: String? {
        get { defaults.string(forKey: Self.pendingHostedLinkKey) }
        set {
            if let newValue { defaults.set(newValue, forKey: Self.pendingHostedLinkKey) }
            else { defaults.removeObject(forKey: Self.pendingHostedLinkKey) }
        }
    }

    private func refreshBackendIdentity() async {
        _ = await auth.currentGoogleIDToken()
    }

    private static func localDateString(now: Date = .now, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(in: TimeZone.current, from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return String(ISO8601DateFormatter().string(from: now).prefix(10))
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

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
    @Published private(set) var isAutoSortingIncome = false
    @Published private(set) var incomeOrganizationMessage: String?

    private let api: any FinanceDataProviding
    private let auth: AuthenticationManager
    private let defaults: UserDefaults
    private let snapshotStore: ProtectedSnapshotStore<FinanceOverview>
    private let categoryMemoryStore: ProtectedSnapshotStore<FinanceCategoryMemory>
    private let incomeAIReviewStore: ProtectedSnapshotStore<IncomeAIReviewLedger>
    private var categoryMemory: FinanceCategoryMemory
    private var incomeAIReviewLedger: IncomeAIReviewLedger
    private var lastNetworkRefreshAt: Date?
    private var smartCategorizationTask: Task<Void, Never>?
    private var smartCategorizationGeneration = UUID()
    private var incomeOrganizationTask: Task<Void, Never>?
    private var incomeOrganizationGeneration = UUID()
    private var incomeRequestGeneration = UUID()

    private static let pendingHostedLinkKey = "orbit.finance.pendingHostedLink"
    private static let automaticAIOrganizationKey = "orbit.ai.financeAutoOrganizeEnabled"
    private static let automaticRefreshInterval: TimeInterval = 120
    private static let automaticIncomeConfidence = 0.80
    private static let automaticIncomeRunLimit = 48
    private static let smartCategorizationRunLimit = 96
    private static let smartCategorizationBatchSize = 24

    init(
        api: any FinanceDataProviding,
        auth: AuthenticationManager,
        defaults: UserDefaults = .standard,
        snapshotStore: ProtectedSnapshotStore<FinanceOverview>? = nil,
        categoryMemoryStore: ProtectedSnapshotStore<FinanceCategoryMemory>? = nil,
        incomeAIReviewStore: ProtectedSnapshotStore<IncomeAIReviewLedger>? = nil
    ) {
        self.api = api
        self.auth = auth
        self.defaults = defaults
        self.snapshotStore = snapshotStore
            ?? ProtectedSnapshotStore(filename: "orbit-finance-overview-v1.json")
        self.categoryMemoryStore = categoryMemoryStore
            ?? ProtectedSnapshotStore(filename: "orbit-finance-category-memory-v1.json")
        self.incomeAIReviewStore = incomeAIReviewStore
            ?? ProtectedSnapshotStore(filename: "orbit-finance-income-ai-reviews-v1.json")

        let ownerID = UserSession.restore()?.userID
        let savedMemory = self.categoryMemoryStore.load(ownerID: ownerID)?.value
        self.categoryMemory = savedMemory?.version == FinanceCategoryMemory.currentVersion
            ? savedMemory!
            : FinanceCategoryMemory()
        let savedIncomeReviews = self.incomeAIReviewStore.load(ownerID: ownerID)?.value
        self.incomeAIReviewLedger = savedIncomeReviews?.version == IncomeAIReviewLedger.currentVersion
            ? savedIncomeReviews!
            : IncomeAIReviewLedger()

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

    func userCategory(for transaction: FinanceTransaction) -> FinanceSmartCategory? {
        let key = FinanceCategoryName.merchantKey(for: transaction)
        return categoryMemory.userRulesByMerchant[key]?.category
    }

    func recurringDecision(for transaction: FinanceTransaction) -> FinanceRecurringDecision {
        categoryMemory.recurringDecision(for: transaction)
    }

    func recurringDecision(for payment: FinanceRecurringPayment) -> FinanceRecurringDecision {
        categoryMemory.recurringDecision(for: payment)
    }

    @discardableResult
    func setCategory(
        _ category: FinanceSmartCategory?,
        for transaction: FinanceTransaction
    ) -> Bool {
        var updated = categoryMemory
        if let category {
            updated.setUserCategory(category, for: transaction)
        } else {
            updated.setAutomaticCategory(for: transaction)
        }
        return commitCategoryMemory(updated)
    }

    @discardableResult
    func setRecurringDecision(
        _ decision: FinanceRecurringDecision,
        for transaction: FinanceTransaction
    ) -> Bool {
        var updated = categoryMemory
        updated.setRecurringDecision(decision, for: transaction)
        return commitCategoryMemory(updated)
    }

    @discardableResult
    func setRecurringDecision(
        _ decision: FinanceRecurringDecision,
        for payment: FinanceRecurringPayment
    ) -> Bool {
        var updated = categoryMemory
        updated.setRecurringDecision(decision, for: payment)
        return commitCategoryMemory(updated)
    }

    @discardableResult
    func organize(
        transaction: FinanceTransaction,
        category: FinanceSmartCategory?,
        recurringDecision: FinanceRecurringDecision
    ) -> Bool {
        var updated = categoryMemory
        if let category {
            updated.setUserCategory(category, for: transaction)
        } else {
            updated.setAutomaticCategory(for: transaction)
        }
        updated.setRecurringDecision(recurringDecision, for: transaction)
        return commitCategoryMemory(updated)
    }

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
        cancelIncomeOrganization(clearMessage: false)
        let generation = UUID()
        incomeRequestGeneration = generation
        let previousState = incomeState
        if showLoading, incomeState.value == nil { incomeState = .loading }

        do {
            await refreshBackendIdentity()
            try Task.checkCancellation()
            guard incomeRequestGeneration == generation else { return }
            let overview = try await api.fetchIncomeOverview(
                asOfDate: Self.localDateString(),
                timeZone: TimeZone.current.identifier
            )
            try Task.checkCancellation()
            guard incomeRequestGeneration == generation else { return }
            incomeState = overview.summaries.isEmpty ? .empty : .loaded(overview)
            scheduleAutomaticIncomeOrganization(for: overview)
        } catch is CancellationError {
            // Never strand the page in a loading state after navigation or
            // background cancellation.
            if incomeRequestGeneration == generation { incomeState = previousState }
        } catch {
            if incomeRequestGeneration == generation {
                incomeState = .failed(error.localizedDescription)
            }
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

        cancelIncomeOrganization(clearMessage: false)
        let generation = UUID()
        incomeRequestGeneration = generation
        await refreshBackendIdentity()
        try Task.checkCancellation()
        guard incomeRequestGeneration == generation else { throw CancellationError() }
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
        try Task.checkCancellation()
        guard incomeRequestGeneration == generation else { throw CancellationError() }
        incomeState = overview.summaries.isEmpty ? .empty : .loaded(overview)
        scheduleAutomaticIncomeOrganization(for: overview)
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

    /// Starts a bounded background pass for merchants that still need either a
    /// spending category or a recurring-payment decision.
    func organizeUnknownTransactions() {
        scheduleSmartCategorization(for: state.value)
    }

    func organizeFinancesWithAI() {
        scheduleSmartCategorization(for: state.value)
        if let income = incomeState.value {
            scheduleAutomaticIncomeOrganization(for: income)
        }
    }

    func organizeIncomeWithAI(force: Bool = false) {
        guard let income = incomeState.value else { return }
        if force {
            var updatedLedger = incomeAIReviewLedger
            for transaction in income.summaries.flatMap(\.needsReviewTransactions) {
                updatedLedger.remove(transactionID: transaction.id)
            }
            if incomeAIReviewStore.save(updatedLedger, ownerID: UserSession.restore()?.userID) {
                incomeAIReviewLedger = updatedLedger
            } else {
                incomeOrganizationMessage = "Orbit could not securely reset the AI review queue. Try again."
                return
            }
        }
        scheduleAutomaticIncomeOrganization(for: income)
    }

    func setAutomaticAIOrganization(enabled: Bool) {
        defaults.set(enabled, forKey: Self.automaticAIOrganizationKey)
        if enabled {
            organizeFinancesWithAI()
        } else {
            cancelAutomaticAIOrganization()
        }
    }

    /// Stops in-flight model work without changing the owner's saved opt-in.
    /// This is used when the OpenAI connection is removed or the session ends.
    func cancelAutomaticAIOrganization() {
        cancelSmartCategorization(clearMessage: true)
        cancelIncomeOrganization(clearMessage: true)
    }

    func disconnect(itemID: String) async throws {
        await refreshBackendIdentity()
        _ = try await api.disconnectFinanceConnection(itemID)
        lastNetworkRefreshAt = nil
        await load(showLoading: false, forceRefresh: true)
    }

    func clear() {
        cancelAutomaticAIOrganization()
        incomeRequestGeneration = UUID()
        state = .disconnected
        incomeState = .disconnected
        isConnecting = false
        isRefreshing = false
        hostedLinkNotice = nil
        refreshError = nil
        snapshotDate = nil
        lastNetworkRefreshAt = nil
        pendingHostedLinkID = nil
        snapshotStore.remove()
        categoryMemoryStore.remove()
        incomeAIReviewStore.remove()
        categoryMemory = FinanceCategoryMemory()
        incomeAIReviewLedger = IncomeAIReviewLedger()
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
        cancelSmartCategorization(clearMessage: false)
        guard let overview,
              automaticAIOrganizationEnabled,
              let key = KeychainStore.get(KeychainKeys.openAIKey),
              !key.isEmpty else {
            smartCategorizationMessage = nil
            return
        }
        let samples = categoryMemory.unclassifiedSamples(
            in: overview,
            limit: Self.smartCategorizationRunLimit
        )
        guard !samples.isEmpty else {
            return
        }

        let generation = UUID()
        smartCategorizationGeneration = generation
        smartCategorizationTask = Task { [weak self] in
            guard let self else { return }
            await self.runSmartCategorization(
                samples: samples,
                apiKey: key,
                generation: generation
            )
        }
    }

    private func runSmartCategorization(
        samples: [FinanceMerchantSample],
        apiKey: String,
        generation: UUID
    ) async {
        isSmartCategorizing = true
        smartCategorizationMessage = nil
        defer {
            if smartCategorizationGeneration == generation {
                isSmartCategorizing = false
            }
        }
        do {
            var learnedRules: [FinanceMerchantCategoryRule] = []
            for offset in stride(
                from: 0,
                to: samples.count,
                by: Self.smartCategorizationBatchSize
            ) {
                let end = min(offset + Self.smartCategorizationBatchSize, samples.count)
                let batch = Array(samples[offset..<end])
                let learnedRulesForBatch = try await FinanceCategoryIntelligence(apiKey: apiKey).classify(batch)
                try Task.checkCancellation()
                guard smartCategorizationGeneration == generation else { return }
                learnedRules.append(contentsOf: learnedRulesForBatch)
            }
            guard !learnedRules.isEmpty else { return }

            // Rebase on the latest owner memory after all network awaits so a
            // correction made while AI was running can never be lost.
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
            let learnedCount = learnedRules.count
            smartCategorizationMessage = "Orbit AI organized \(learnedCount) merchant pattern\(learnedCount == 1 ? "" : "s") for future transactions."
        } catch is CancellationError {
            // A newer bank sync superseded this batch.
        } catch {
            guard !Task.isCancelled, smartCategorizationGeneration == generation else { return }
            smartCategorizationMessage = "Smart categorization will retry later: \(error.localizedDescription)"
        }
    }

    private func scheduleAutomaticIncomeOrganization(for overview: IncomeOverview) {
        cancelIncomeOrganization(clearMessage: false)

        guard automaticAIOrganizationEnabled,
              let ownerID = UserSession.restore()?.userID,
              !ownerID.isEmpty,
              let key = KeychainStore.get(KeychainKeys.openAIKey),
              !key.isEmpty else {
            incomeOrganizationMessage = nil
            return
        }

        var seen = Set<String>()
        let candidates = overview.summaries
            .flatMap(\.needsReviewTransactions)
            .filter {
                !$0.pending
                    && !incomeAIReviewLedger.contains(transactionID: $0.id)
                    && seen.insert($0.id).inserted
            }
            .sorted {
                $0.date > $1.date || ($0.date == $1.date && $0.id < $1.id)
            }
        guard !candidates.isEmpty else {
            isAutoSortingIncome = false
            return
        }

        let generation = UUID()
        incomeOrganizationGeneration = generation
        let requestGeneration = incomeRequestGeneration
        let history = state.value?.recentTransactions ?? []
        incomeOrganizationTask = Task { [weak self] in
            guard let self else { return }
            await self.runAutomaticIncomeOrganization(
                candidates: candidates,
                history: history,
                apiKey: key,
                ownerID: ownerID,
                generation: generation,
                requestGeneration: requestGeneration
            )
        }
    }

    private func runAutomaticIncomeOrganization(
        candidates: [IncomeTransaction],
        history: [FinanceTransaction],
        apiKey: String,
        ownerID: String,
        generation: UUID,
        requestGeneration: UUID
    ) async {
        isAutoSortingIncome = true
        incomeOrganizationMessage = nil
        defer {
            if incomeOrganizationGeneration == generation {
                isAutoSortingIncome = false
            }
        }

        do {
            var sortedCount = 0
            var reviewCount = 0
            var ledgerSaveFailed = false
            let runCandidates = Array(candidates.prefix(Self.automaticIncomeRunLimit))
            let batches = stride(from: 0, to: runCandidates.count, by: 12).map { offset in
                Array(runCandidates[offset..<min(offset + 12, runCandidates.count)])
            }

            for batch in batches {
                try Task.checkCancellation()
                guard incomeOrganizationGeneration == generation,
                      incomeRequestGeneration == requestGeneration else { return }
                let suggestions = try await IncomeIntelligence(apiKey: apiKey).suggestBatch(
                    transactions: batch,
                    transactionHistory: history
                )
                try Task.checkCancellation()
                guard incomeOrganizationGeneration == generation,
                      incomeRequestGeneration == requestGeneration else { return }

                reviewCount += max(0, batch.count - suggestions.count)
                for suggestion in suggestions {
                    try Task.checkCancellation()
                    guard incomeOrganizationGeneration == generation,
                          incomeRequestGeneration == requestGeneration else { return }
                    let isDecisive = suggestion.classification != .needsReview
                        && suggestion.confidence >= Self.automaticIncomeConfidence

                    if isDecisive {
                        await refreshBackendIdentity()
                        try Task.checkCancellation()
                        guard incomeOrganizationGeneration == generation,
                              incomeRequestGeneration == requestGeneration else { return }
                        let overview = try await api.classifyIncomeTransaction(
                            suggestion.transactionID,
                            request: IncomeClassificationRequest(
                                classification: suggestion.classification,
                                sourceName: suggestion.classification == .income ? suggestion.sourceName : nil,
                                type: suggestion.classification == .income ? suggestion.sourceType : nil,
                                asOfDate: Self.localDateString(),
                                timeZone: TimeZone.current.identifier,
                                decisionSource: .ai,
                                confidence: suggestion.confidence,
                                reason: suggestion.reason
                            )
                        )
                        try Task.checkCancellation()
                        guard incomeOrganizationGeneration == generation,
                              incomeRequestGeneration == requestGeneration else { return }
                        incomeState = overview.summaries.isEmpty ? .empty : .loaded(overview)
                        sortedCount += 1
                    } else {
                        reviewCount += 1
                    }

                    var updatedLedger = incomeAIReviewLedger
                    updatedLedger.record([suggestion])
                    if incomeAIReviewStore.save(updatedLedger, ownerID: ownerID) {
                        incomeAIReviewLedger = updatedLedger
                    } else {
                        ledgerSaveFailed = true
                    }
                }
            }

            let deferredCount = max(0, candidates.count - runCandidates.count)
            if sortedCount > 0, reviewCount > 0 {
                incomeOrganizationMessage = "Orbit AI sorted \(sortedCount) deposit\(sortedCount == 1 ? "" : "s"); \(reviewCount) still need your review."
            } else if sortedCount > 0 {
                incomeOrganizationMessage = "Orbit AI sorted \(sortedCount) new deposit\(sortedCount == 1 ? "" : "s") automatically."
            } else if reviewCount > 0 {
                incomeOrganizationMessage = "Orbit AI checked new deposits and left \(reviewCount) uncertain item\(reviewCount == 1 ? "" : "s") for you."
            }
            if deferredCount > 0 {
                incomeOrganizationMessage = "\(incomeOrganizationMessage ?? "Orbit AI finished this pass.") \(deferredCount) older deposit\(deferredCount == 1 ? "" : "s") will be checked on the next refresh."
            }
            if ledgerSaveFailed {
                incomeOrganizationMessage = "\(incomeOrganizationMessage ?? "Orbit AI finished this pass.") A secure review receipt could not be saved, so Orbit may safely recheck an item later."
            }
        } catch is CancellationError {
            // A newer Income refresh replaced this pass.
        } catch {
            guard !Task.isCancelled,
                  incomeOrganizationGeneration == generation,
                  incomeRequestGeneration == requestGeneration else { return }
            incomeOrganizationMessage = "AI income sorting will retry later: \(error.localizedDescription)"
        }
    }

    private var automaticAIOrganizationEnabled: Bool {
        if defaults.object(forKey: Self.automaticAIOrganizationKey) == nil { return false }
        return defaults.bool(forKey: Self.automaticAIOrganizationKey)
    }

    private func cancelSmartCategorization(clearMessage: Bool) {
        smartCategorizationGeneration = UUID()
        smartCategorizationTask?.cancel()
        smartCategorizationTask = nil
        isSmartCategorizing = false
        if clearMessage { smartCategorizationMessage = nil }
    }

    private func cancelIncomeOrganization(clearMessage: Bool) {
        incomeOrganizationGeneration = UUID()
        incomeOrganizationTask?.cancel()
        incomeOrganizationTask = nil
        isAutoSortingIncome = false
        if clearMessage { incomeOrganizationMessage = nil }
    }

    private func commitCategoryMemory(_ updated: FinanceCategoryMemory) -> Bool {
        let ownerID = UserSession.restore()?.userID
        guard categoryMemoryStore.save(updated, ownerID: ownerID) else {
            smartCategorizationMessage = "Your Finance correction could not be saved securely. Try again."
            return false
        }
        categoryMemory = updated
        if let current = state.value {
            let organized = categoryMemory.applying(to: current)
            state = organized.accounts.isEmpty ? .empty : .loaded(organized)
            snapshotStore.save(organized, ownerID: ownerID)
        }
        return true
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

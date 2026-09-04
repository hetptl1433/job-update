import AuthenticationServices
import Charts
import SwiftUI

/// One-glance money view for every institution the user explicitly connects.
/// Plaid Hosted Link handles OAuth; Orbit displays only the normalized backend
/// result after its backend has verified Plaid's signed completion webhook.
struct FinanceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var finance: FinanceRepository
    @AppStorage("orbit.ai.financeContextEnabled") private var shareWithAssistant = false

    @State private var isPreparingLink = false
    @State private var errorMessage: String?
    @State private var institutionToDisconnect: FinanceInstitution?
    @State private var authenticationSession: HostedLinkAuthenticationSession?
    @State private var spendingPeriod: FinanceSpendingPeriod = .thisMonth
    @State private var selectedSpendingCategoryID: String?

    var body: some View {
        NavigationStack(path: $app.financePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    content
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Finance")
            .toolbar {
                if finance.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: beginConnection) {
                            Image(systemName: "plus")
                        }
                        .disabled(isPreparingLink || finance.isConnecting)
                        .accessibilityLabel("Connect another financial institution")
                    }
                }
            }
            .refreshable {
                if finance.hasPendingHostedLink { await finance.resumeHostedLinkIfNeeded() }
                else { await finance.load(showLoading: false, forceRefresh: true) }
            }
            .task {
                if finance.hasPendingHostedLink { await finance.resumeHostedLinkIfNeeded() }
                else { await finance.load() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      authenticationSession == nil,
                      finance.hasPendingHostedLink else { return }
                Task { await finance.resumeHostedLinkIfNeeded() }
            }
            .onChange(of: app.connections.aiConnected) { _, connected in
                if connected { finance.organizeUnknownTransactions() }
            }
            .onChange(of: finance.hostedLinkNotice) { _, notice in
                guard let notice else { return }
                errorMessage = notice
                finance.clearHostedLinkNotice()
            }
            .alert("Finance", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .confirmationDialog(
                "Disconnect \(institutionToDisconnect?.name ?? "institution")?",
                isPresented: Binding(
                    get: { institutionToDisconnect != nil },
                    set: { if !$0 { institutionToDisconnect = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    guard let item = institutionToDisconnect else { return }
                    institutionToDisconnect = nil
                    Task {
                        do { try await finance.disconnect(itemID: item.id) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { institutionToDisconnect = nil }
            } message: {
                Text("Orbit will revoke this Plaid connection and remove its synced financial data.")
            }
            .navigationDestination(for: FinanceRoute.self) { route in
                switch route {
                case .income:
                    IncomeView()
                case .recurring:
                    RecurringPaymentsView()
                case .transactions:
                    FinanceTransactionsView()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch finance.state {
        case .loading:
            LoadingStateView(message: "Loading your financial overview…")
                .cardSurface()
        case .loaded(let overview):
            overviewContent(overview)
        case .idle:
            LoadingStateView(message: "Preparing your financial overview…")
                .cardSurface()
        case .empty:
            connectState
        case .failed(let message):
            InfoStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load Finance",
                message: message,
                actionTitle: "Try again"
            ) { Task { await finance.load() } }
            .cardSurface()
        case .disconnected:
            if finance.isBackendConfigured { connectState } else { backendRequiredState }
        }
    }

    private var backendRequiredState: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            InfoStateView(
                systemImage: "lock.shield",
                title: "Finance server required",
                message: "Chase and other real accounts require Orbit's secure HTTPS backend. Bank sign-in opens in an Apple-protected Plaid window; credentials never enter Orbit."
            )
            .cardSurface()

            Label(
                "Bank credentials and Plaid access tokens never belong in the iPhone app.",
                systemImage: "hand.raised"
            )
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var connectState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            InfoStateView(
                systemImage: "building.columns",
                title: "Your money, together",
                message: "Connect Chase, credit cards, banks and investment accounts in Plaid's secure sign-in window. It returns to Orbit automatically when you finish."
            )
            .cardSurface()
            connectButton(title: "Connect financial account")
            privacyCard
        }
    }

    private func overviewContent(_ overview: FinanceOverview) -> some View {
        let spending = FinanceSpendingAnalysis.make(
            overview: overview,
            period: spendingPeriod
        )
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            refreshStatus
            financialPositionCard(overview)
            summaryGrid(overview)
            cashFlowCard(overview)
            FinanceSmartInsightCard(
                overview: overview,
                spending: spending,
                isOrganizing: finance.isSmartCategorizing,
                learnedMerchantCount: finance.learnedMerchantCategoryCount,
                categorizationMessage: finance.smartCategorizationMessage
            )
            spendingSection(overview, analysis: spending)
            recurringPaymentsSection(overview)
            incomeDestination
            transactionsSection(overview)
            accountsSection(overview)
            institutionsSection(overview)
            privacyCard
        }
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if finance.isRefreshing {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Updating connected accounts…")
                Spacer()
                if let snapshotDate = finance.snapshotDate {
                    Text(snapshotDate.formatted(.relative(presentation: .named)))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        } else if let message = finance.refreshError {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing your saved overview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Button("Retry") {
                    Task { await finance.load(showLoading: false, forceRefresh: true) }
                }
                .font(.caption.weight(.semibold))
            }
            .cardSurface(padding: AppTheme.Spacing.md)
        } else if let snapshotDate = finance.snapshotDate {
            Label(
                "Updated \(snapshotDate.formatted(.relative(presentation: .named)))",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var incomeDestination: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Explore")
            NavigationLink(value: FinanceRoute.income) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 40, height: 40)
                        .background(
                            AppTheme.secondarySurface,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Income")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(incomeDestinationSubtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .contentShape(Rectangle())
                .cardSurface()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows confirmed earnings separately from all account inflows")
        }
    }

    private var incomeDestinationSubtitle: String {
        switch finance.incomeState {
        case .loaded(let overview):
            guard let first = overview.summaries.first else {
                return "Confirmed earnings, sources, history and calculator"
            }
            if overview.summaries.count > 1 {
                return "Confirmed earnings tracked separately in \(overview.summaries.count) currencies"
            }
            return "\(money(NSDecimalNumber(decimal: first.thisMonth.confirmed).doubleValue, code: first.currencyCode)) confirmed this month"
        case .loading:
            return "Classifying deposits and reconciling transfers…"
        case .failed:
            return "Income needs a refresh"
        default:
            return "Confirmed earnings—not transfers, refunds or every inflow"
        }
    }

    private func financialPositionCard(_ overview: FinanceOverview) -> some View {
        FinancePositionCard(overview: overview)
    }

    private func summaryGrid(_ overview: FinanceOverview) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppTheme.Spacing.md
        ) {
            FinanceMetricCard(
                title: "This month in",
                value: money(overview.adjustedMonthlyInflow, code: overview.currencyCode),
                systemImage: "arrow.down.left",
                tint: AppTheme.success
            )
            FinanceMetricCard(
                title: "This month spent",
                value: money(overview.adjustedMonthlyOutflow, code: overview.currencyCode),
                systemImage: "arrow.up.right",
                tint: AppTheme.coral
            )
        }
    }

    private func cashFlowCard(_ overview: FinanceOverview) -> some View {
        let total = max(overview.adjustedMonthlyInflow + overview.adjustedMonthlyOutflow, 1)
        let inflowShare = overview.adjustedMonthlyInflow / total
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTHLY IN VS SPENT").sectionLabel()
                    Text(money(overview.monthlyNetFlow, code: overview.currencyCode))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(overview.monthlyNetFlow >= 0 ? AppTheme.success : AppTheme.coral)
                }
                Spacer()
                Text(overview.monthlyNetFlow >= 0 ? "Net positive" : "Net negative")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    Capsule()
                        .fill(AppTheme.success)
                        .frame(width: max(4, geometry.size.width * inflowShare))
                    Capsule().fill(AppTheme.coral)
                }
            }
            .frame(height: 7)
            HStack {
                Label("In", systemImage: "circle.fill").foregroundStyle(AppTheme.success)
                Spacer()
                Label("Spent", systemImage: "circle.fill").foregroundStyle(AppTheme.coral)
            }
            .font(.caption2)
        }
        .cardSurface()
    }

    private func recurringPaymentsSection(_ overview: FinanceOverview) -> some View {
        let payments = overview.detectedRecurringPayments
        let confirmedCount = overview.confirmedRecurringPayments.count
        let possibleCount = overview.possibleSubscriptions.count
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(
                title: "Recurring payments",
                actionTitle: payments.isEmpty ? nil : "See all",
                action: payments.isEmpty ? nil : { app.financePath.append(.recurring) }
            )

            if payments.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Image(systemName: "repeat")
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.secondarySurface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No recurring charges detected yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("Orbit combines posted-charge patterns with merchant knowledge. New possibilities appear for review before they affect totals.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CONFIRMED EACH MONTH").sectionLabel()
                            Text(money(overview.detectedMonthlyRecurringTotal, code: overview.currencyCode))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.primaryText)
                        }
                        Spacer()
                        Text(recurringCountLabel(confirmed: confirmedCount, possible: possibleCount))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(AppTheme.Spacing.lg)

                    Divider().overlay(AppTheme.separator)

                    ForEach(Array(payments.prefix(3).enumerated()), id: \.element.id) { index, payment in
                        FinanceRecurringPaymentRow(payment: payment)
                        if index < min(payments.count, 3) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    private func recurringCountLabel(confirmed: Int, possible: Int) -> String {
        if possible == 0 { return "\(confirmed) active" }
        if confirmed == 0 { return "\(possible) to review" }
        return "\(confirmed) active · \(possible) review"
    }

    private func spendingSection(
        _ overview: FinanceOverview,
        analysis: FinanceSpendingAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(
                title: "Spending breakdown",
                actionTitle: overview.recentTransactions.isEmpty ? nil : "See all",
                action: overview.recentTransactions.isEmpty ? nil : {
                    app.financePath.append(.transactions)
                }
            )
            FinanceSpendingDashboardCard(
                analysis: analysis,
                selectedCategoryID: $selectedSpendingCategoryID,
                period: $spendingPeriod
            )
        }
    }

    private func accountsSection(_ overview: FinanceOverview) -> some View {
        let bankAccounts = overview.accounts.filter { $0.group == .bank }
        let creditCards = overview.accounts.filter { $0.group == .creditCards }
        let otherAccounts = overview.accounts.filter { $0.group == .other }

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Accounts", actionTitle: "Add", action: beginConnection)

            FinanceAccountsBox(
                group: .bank,
                accounts: bankAccounts,
                overview: overview,
                linksToInstitution: true
            )
            FinanceAccountsBox(
                group: .creditCards,
                accounts: creditCards,
                overview: overview,
                linksToInstitution: true
            )
            if !otherAccounts.isEmpty {
                FinanceAccountsBox(
                    group: .other,
                    accounts: otherAccounts,
                    overview: overview,
                    linksToInstitution: true
                )
            }
        }
    }

    private func transactionsSection(_ overview: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(
                title: "Recent activity",
                actionTitle: overview.recentTransactions.isEmpty ? nil : "See all",
                action: overview.recentTransactions.isEmpty ? nil : {
                    app.financePath.append(.transactions)
                }
            )
            if overview.recentTransactions.isEmpty {
                Text("No transactions are available yet. Plaid may still be preparing the first sync.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(overview.recentTransactions.prefix(12).enumerated()), id: \.element.id) { index, transaction in
                        FinanceTransactionRow(transaction: transaction)
                        if index < min(overview.recentTransactions.count, 12) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    private func institutionsSection(_ overview: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Connections")
            VStack(spacing: 0) {
                ForEach(Array(overview.institutions.enumerated()), id: \.element.id) { index, institution in
                    HStack(spacing: 0) {
                        NavigationLink {
                            FinanceInstitutionDetailView(
                                institution: institution,
                                initialOverview: overview
                            )
                        } label: {
                            HStack(spacing: AppTheme.Spacing.md) {
                                FinanceInstitutionMark(name: institution.name, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(institution.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text("\(institution.accountCount) account\(institution.accountCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer(minLength: AppTheme.Spacing.sm)
                                if institution.needsAttention {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(AppTheme.warning)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .padding(.leading, AppTheme.Spacing.lg)
                            .padding(.vertical, AppTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows only this institution's accounts and activity")

                        Menu {
                            Button("Disconnect", role: .destructive) {
                                institutionToDisconnect = institution
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(width: 48, height: 48)
                        }
                        .accessibilityLabel("Manage \(institution.name)")
                    }
                    if index < overview.institutions.count - 1 { Divider().overlay(AppTheme.separator) }
                }
            }
            .cardSurface(padding: 0)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Toggle("Allow Finance summary in Assistant", isOn: $shareWithAssistant)
                .font(.subheadline.weight(.semibold))
                .tint(AppTheme.brand)
            Text("Off by default. When enabled, Orbit sends compact totals and relevant transaction summaries to your configured AI—never Plaid tokens or bank credentials.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private func connectButton(title: String) -> some View {
        Button(action: beginConnection) {
            HStack {
                if isPreparingLink || finance.isConnecting { ProgressView().tint(AppTheme.onBrand) }
                else { Image(systemName: "plus") }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isPreparingLink || finance.isConnecting)
    }

    private func beginConnection() {
        guard !isPreparingLink, !finance.isConnecting else { return }
        isPreparingLink = true
        errorMessage = nil
        Task {
            do {
                let launch = try await finance.createHostedLink()
                presentHostedLink(launch.hostedLinkURL)
            } catch {
                errorMessage = error.localizedDescription
                isPreparingLink = false
            }
        }
    }

    private func presentHostedLink(_ url: URL) {
        let session = HostedLinkAuthenticationSession()
        authenticationSession = session
        let didStart = session.start(url: url) { callbackURL, error in
            authenticationSession = nil
            isPreparingLink = false

            if let callbackURL {
                _ = app.handleOpenURL(callbackURL)
            } else if let error,
                      (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = error.localizedDescription
            }

            // Cancellation is intentionally not shown as an error. The signed
            // webhook is authoritative and may arrive just after the callback.
            Task { await finance.resumeHostedLinkIfNeeded() }
        }
        isPreparingLink = false
        if !didStart {
            authenticationSession = nil
            errorMessage = "Orbit couldn't open Plaid's secure sign-in window. Please try again."
        }
    }

    private func money(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }
}

/// Retains the system authentication session for the full Hosted Link flow and
/// closes it only when Plaid returns to Orbit's registered custom URL scheme.
@MainActor
private final class HostedLinkAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    @discardableResult
    func start(
        url: URL,
        completion: @escaping (_ callbackURL: URL?, _ error: Error?) -> Void
    ) -> Bool {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "orbit"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.session = nil
                completion(callbackURL, error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        return session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if let window = scene.windows.first(where: \.isKeyWindow) { return window }
        }
        return ASPresentationAnchor()
    }
}

private struct FinanceMetricCard: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Image(systemName: systemImage).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct FinancePositionCard: View {
    var overview: FinanceOverview

    private var totalPosition: Double {
        overview.totalCash + overview.totalInvestments - overview.totalCreditBalance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TOTAL POSITION")
                        .font(.caption.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(money(totalPosition))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Cash and investments minus card balances")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Label("Live", systemImage: "circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AppTheme.success.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.success.opacity(0.2), lineWidth: 1))
            }

            HStack(spacing: 0) {
                FinancePositionValue(
                    title: "Cash",
                    value: money(overview.totalCash)
                )
                positionDivider
                FinancePositionValue(
                    title: "Invested",
                    value: money(overview.totalInvestments)
                )
                positionDivider
                FinancePositionValue(
                    title: "Cards",
                    value: money(overview.totalCreditBalance)
                )
            }
        }
        .padding(AppTheme.Spacing.xl)
        .background(
            LinearGradient(
                colors: [AppTheme.elevatedSurface, AppTheme.primarySurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(AppTheme.brandGradient)
                .frame(width: 64, height: 3)
                .padding(.leading, AppTheme.Spacing.xl)
        }
        .shadow(
            color: AppTheme.Shadow.cardColor,
            radius: AppTheme.Shadow.cardRadius,
            x: 0,
            y: AppTheme.Shadow.cardY
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Total position (money(totalPosition)). Cash (money(overview.totalCash)), "
                + "investments (money(overview.totalInvestments)), cards owed (money(overview.totalCreditBalance))."
        )
    }

    private var positionDivider: some View {
        Rectangle()
            .fill(AppTheme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func money(_ amount: Double) -> String {
        FinanceDashboardFormat.money(amount, code: overview.currencyCode)
    }
}

private struct FinancePositionValue: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FinanceSmartInsightCard: View {
    var overview: FinanceOverview
    var spending: FinanceSpendingAnalysis
    var isOrganizing = false
    var learnedMerchantCount = 0
    var categorizationMessage: String? = nil

    private var recurringShare: Double {
        guard spending.period == .thisMonth, spending.totalSpent > 0 else { return 0 }
        return min(overview.detectedMonthlyRecurringTotal / spending.totalSpent, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accent, in: Circle())
                Text("ORBIT INTELLIGENCE")
                    .sectionLabel()
                Spacer()
                Text(intelligenceStatus)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.secondarySurface, in: Capsule())
            }

            if let topCategory = spending.topCategory {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(FinanceCategoryVisuals.displayName(for: topCategory.name)) leads your spending")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(insightDescription(topCategory))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    FinanceInsightMetric(
                        title: "Recurring / mo",
                        value: money(overview.detectedMonthlyRecurringTotal),
                        systemImage: "repeat",
                        tint: AppTheme.purple
                    )
                    FinanceInsightMetric(
                        title: "Average purchase",
                        value: spending.transactionCount > 0 ? money(spending.averageTransaction) : "—",
                        systemImage: "divide",
                        tint: AppTheme.info
                    )
                    FinanceInsightMetric(
                        title: "Largest purchase",
                        value: spending.largestTransaction.map { money($0.amount) } ?? "—",
                        systemImage: "arrow.up.right",
                        tint: AppTheme.coral
                    )
                }

                if spending.period == .thisMonth, recurringShare > 0 {
                    Label(
                        "Recurring charges are \(percent(recurringShare)) of this month's spending.",
                        systemImage: "lightbulb"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your smart snapshot is getting ready")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Insights will appear as soon as posted transactions arrive for this period.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Divider().overlay(AppTheme.separator)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if isOrganizing {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("AI is organizing new merchants; saved decisions will be reused.")
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                } else if learnedMerchantCount > 0 {
                    Label(
                        "\(learnedMerchantCount) learned merchant categor\(learnedMerchantCount == 1 ? "y" : "ies") are reused automatically.",
                        systemImage: "brain.head.profile"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                } else if let categorizationMessage {
                    Label(categorizationMessage, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Label(
                    "Food & Drink stays separate. Card payments, transfers and pending charges are excluded.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .cardSurface()
    }

    private var intelligenceStatus: String {
        if isOrganizing { return "ORGANIZING" }
        if learnedMerchantCount > 0 { return "\(learnedMerchantCount) LEARNED" }
        return "AUTO-UPDATED"
    }

    private func insightDescription(_ category: FinanceSpendingBreakdown) -> String {
        let amount = money(category.amount)
        let share = percent(category.share)
        if category.transactionCount > 0 {
            let purchase = category.transactionCount == 1 ? "purchase" : "purchases"
            return "It accounts for \(share) (\(amount)) across \(category.transactionCount) \(purchase) in \(spending.period.label.lowercased())."
        }
        return "It accounts for \(share) (\(amount)) of spending in \(spending.period.label.lowercased())."
    }

    private func money(_ amount: Double) -> String {
        FinanceDashboardFormat.money(amount, code: spending.currencyCode)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct FinanceInsightMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(
            AppTheme.secondarySurface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        )
    }
}

private struct FinanceSpendingDashboardCard: View {
    var analysis: FinanceSpendingAnalysis
    @Binding var selectedCategoryID: String?
    @Binding var period: FinanceSpendingPeriod

    private var categories: [FinanceSpendingChartCategory] {
        FinanceSpendingChartCategory.displayCategories(from: analysis.categories)
    }

    private var selectedCategory: FinanceSpendingChartCategory? {
        guard let selectedCategoryID else { return nil }
        return categories.first { $0.id == selectedCategoryID }
    }

    private var centerCategory: FinanceSpendingChartCategory? {
        selectedCategory ?? categories.first
    }

    private var selectedTransactions: [FinanceTransaction] {
        guard let selectedCategory else { return [] }
        return analysis.transactions
            .filter { selectedCategory.sourceNames.contains(categoryName(for: $0)) }
            .sorted {
                $0.amount > $1.amount || ($0.amount == $1.amount && $0.date > $1.date)
            }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Picker("Spending period", selection: $period) {
                ForEach(FinanceSpendingPeriod.allCases) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in selectedCategoryID = nil }

            if categories.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "chart.pie")
                        .font(.title2)
                        .foregroundStyle(AppTheme.tertiaryText)
                    Text("No posted spending in \(period.label.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Try another range or pull to refresh after new transactions post.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOTAL SPENT").sectionLabel()
                        Text(money(analysis.totalSpent))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(transactionCountLabel)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Chart(categories) { category in
                    SectorMark(
                        angle: .value("Spent", category.amount),
                        innerRadius: .ratio(0.69),
                        angularInset: 2
                    )
                    .cornerRadius(4)
                    .foregroundStyle(category.color)
                    .opacity(
                        selectedCategory == nil || selectedCategory?.id == category.id
                            ? 1
                            : 0.24
                    )
                }
                .chartLegend(.hidden)
                .frame(height: 210)
                .overlay {
                    if let centerCategory {
                        VStack(spacing: 2) {
                            Text(percent(centerCategory.share))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.primaryText)
                                .monospacedDigit()
                            Text(centerCategory.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                                .frame(maxWidth: 104)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .animation(.snappy(duration: 0.25), value: selectedCategoryID)
                .accessibilityLabel("Spending category chart")
                .accessibilityValue(
                    categories.map { "\($0.name) \(percent($0.share))" }.joined(separator: ", ")
                )

                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(categories) { category in
                        FinanceSpendingCategoryRow(
                            category: category,
                            currencyCode: analysis.currencyCode,
                            isSelected: selectedCategoryID == category.id
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedCategoryID = selectedCategoryID == category.id
                                    ? nil
                                    : category.id
                            }
                        }
                    }
                }

                if let selectedCategory, !selectedTransactions.isEmpty {
                    Divider().overlay(AppTheme.separator)
                    HStack {
                        Text("LARGEST IN \(selectedCategory.name.uppercased())")
                            .sectionLabel()
                            .lineLimit(1)
                        Spacer()
                        Button("Clear") { selectedCategoryID = nil }
                            .font(.caption.weight(.semibold))
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(selectedTransactions.enumerated()), id: \.element.id) { index, transaction in
                            FinanceTransactionRow(transaction: transaction)
                            if index < selectedTransactions.count - 1 {
                                Divider().overlay(AppTheme.separator)
                            }
                        }
                    }
                    .background(
                        AppTheme.secondarySurface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    )
                }
            }
        }
        .cardSurface()
    }

    private var transactionCountLabel: String {
        guard analysis.transactionCount > 0 else { return period.label }
        let noun = analysis.transactionCount == 1 ? "purchase" : "purchases"
        return "\(analysis.transactionCount) \(noun)"
    }

    private func categoryName(for transaction: FinanceTransaction) -> String {
        transaction.displayCategory
    }

    private func money(_ amount: Double) -> String {
        FinanceDashboardFormat.money(amount, code: analysis.currencyCode)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct FinanceSpendingChartCategory: Identifiable {
    var id: String
    var name: String
    var amount: Double
    var share: Double
    var transactionCount: Int
    var sourceNames: Set<String>
    var colorIndex: Int

    var color: Color { FinanceCategoryVisuals.color(at: colorIndex) }

    static func displayCategories(
        from categories: [FinanceSpendingBreakdown]
    ) -> [FinanceSpendingChartCategory] {
        guard categories.count > 6 else {
            return categories.enumerated().map { index, category in
                FinanceSpendingChartCategory(
                    id: category.id,
                    name: FinanceCategoryVisuals.displayName(for: category.name),
                    amount: category.amount,
                    share: category.share,
                    transactionCount: category.transactionCount,
                    sourceNames: [category.name],
                    colorIndex: index
                )
            }
        }

        let leading = categories.prefix(5).enumerated().map { index, category in
            FinanceSpendingChartCategory(
                id: category.id,
                name: FinanceCategoryVisuals.displayName(for: category.name),
                amount: category.amount,
                share: category.share,
                transactionCount: category.transactionCount,
                sourceNames: [category.name],
                colorIndex: index
            )
        }
        let remaining = categories.dropFirst(5)
        let other = FinanceSpendingChartCategory(
            id: "dashboard-everything-else",
            name: "Everything else",
            amount: remaining.reduce(0) { $0 + $1.amount },
            share: remaining.reduce(0) { $0 + $1.share },
            transactionCount: remaining.reduce(0) { $0 + $1.transactionCount },
            sourceNames: Set(remaining.map(\.name)),
            colorIndex: 5
        )
        return leading + [other]
    }
}

private struct FinanceSpendingCategoryRow: View {
    var category: FinanceSpendingChartCategory
    var currencyCode: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: FinanceCategoryVisuals.systemImage(for: category.name))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.color)
                        .frame(width: 32, height: 32)
                        .background(category.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                        Text(countLabel)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(percent(category.share))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                        Text(money(category.amount))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .monospacedDigit()
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? category.color : AppTheme.tertiaryText)
                        .frame(width: 16)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.separator)
                        Capsule()
                            .fill(category.color)
                            .frame(
                                width: max(
                                    4,
                                    geometry.size.width * CGFloat(min(max(category.share, 0), 1))
                                )
                            )
                    }
                }
                .frame(height: 5)
            }
            .padding(AppTheme.Spacing.md)
            .background(
                isSelected ? AppTheme.secondarySurface : Color.clear,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityValue("\(percent(category.share)), \(money(category.amount))")
        .accessibilityHint(isSelected ? "Clears this category filter" : "Shows the largest purchases in this category")
    }

    private var countLabel: String {
        guard category.transactionCount > 0 else { return "Posted spending" }
        return "\(category.transactionCount) \(category.transactionCount == 1 ? "purchase" : "purchases")"
    }

    private func money(_ amount: Double) -> String {
        FinanceDashboardFormat.money(amount, code: currencyCode)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private enum FinanceCategoryVisuals {
    private static let colors: [Color] = [
        AppTheme.info,
        AppTheme.purple,
        AppTheme.coral,
        AppTheme.warning,
        AppTheme.success,
        AppTheme.brandSecondary
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }

    static func displayName(for category: String) -> String {
        let words = category.replacingOccurrences(of: "_", with: " ").split(separator: " ")
        let lowercaseWords: Set<String> = ["and", "of", "the", "for"]
        return words.enumerated().map { index, word in
            let value = String(word)
            if index > 0, lowercaseWords.contains(value.lowercased()) {
                return value.lowercased()
            }
            if value == value.uppercased() {
                return value.lowercased().capitalized
            }
            return value
        }
        .joined(separator: " ")
    }

    static func systemImage(for category: String) -> String {
        let value = category.lowercased()
        if value.contains("credit card") || value.contains("card payment") {
            return "creditcard.fill"
        }
        if value.contains("food") || value.contains("dining") || value.contains("restaurant") {
            return "fork.knife"
        }
        if value.contains("transport") || value.contains("gas") || value.contains("auto") {
            return "car.fill"
        }
        if value.contains("rent") || value.contains("mortgage") || value.contains("home") {
            return "house.fill"
        }
        if value.contains("entertainment") || value.contains("recreation") {
            return "play.rectangle.fill"
        }
        if value.contains("subscription") {
            return "arrow.triangle.2.circlepath"
        }
        if value.contains("travel") {
            return "airplane"
        }
        if value.contains("medical") || value.contains("health") {
            return "cross.case.fill"
        }
        if value.contains("shop") || value.contains("merchandise") {
            return "bag.fill"
        }
        if value.contains("utility") || value.contains("bill") {
            return "bolt.fill"
        }
        if value.contains("loan") || value.contains("bank") || value.contains("financial") {
            return "building.columns.fill"
        }
        return "square.grid.2x2.fill"
    }
}

private enum FinanceDashboardFormat {
    static func money(_ amount: Double, code: String) -> String {
        let roundedToCents = (amount * 100).rounded() / 100
        let hasCents = abs(roundedToCents - roundedToCents.rounded()) >= 0.005
        return roundedToCents.formatted(
            .currency(code: code).precision(.fractionLength(hasCents ? 2 : 0))
        )
    }
}

private struct FinanceAccountRow: View {
    var account: FinanceAccount
    var showsDisclosure = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            FinanceInstitutionMark(name: account.institutionName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.maskedName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(account.institutionName) · \(account.kind.label)")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(account.currentBalance.formatted(
                    .currency(code: account.currencyCode).precision(.fractionLength(0...2))
                ))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                if let available = account.availableBalance {
                    Text("\(available.formatted(.currency(code: account.currencyCode).precision(.fractionLength(0...2)))) available")
                        .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
}

private struct FinanceAccountsBox: View {
    var group: FinanceAccountGroup
    var accounts: [FinanceAccount]
    var overview: FinanceOverview
    var linksToInstitution: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: group.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text("\(accounts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.secondarySurface, in: Capsule())
            }
            .padding(AppTheme.Spacing.lg)

            Divider().overlay(AppTheme.separator)

            if accounts.isEmpty {
                Text(group.emptyMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.lg)
            } else {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    accountRow(account)
                    if index < accounts.count - 1 {
                        Divider().overlay(AppTheme.separator)
                    }
                }
            }
        }
        .cardSurface(padding: 0)
    }

    @ViewBuilder
    private func accountRow(_ account: FinanceAccount) -> some View {
        if linksToInstitution, let institution = overview.institution(for: account) {
            NavigationLink {
                FinanceInstitutionDetailView(
                    institution: institution,
                    initialOverview: overview
                )
            } label: {
                FinanceAccountRow(account: account, showsDisclosure: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows only \(institution.name) accounts and activity")
        } else {
            FinanceAccountRow(account: account)
        }
    }
}

private struct FinanceTransactionsView: View {
    @EnvironmentObject private var finance: FinanceRepository

    @State private var range: FinanceTransactionRange = .oneYear
    @State private var filter: FinanceTransactionFilter = .all
    @State private var selectedCurrencyCode = ""
    @State private var searchText = ""

    private var transactions: [FinanceTransaction] {
        finance.overview?.recentTransactions ?? []
    }

    private var currencyCodes: [String] {
        Array(Set(transactions.map { $0.currencyCode.uppercased() })).sorted()
    }

    private var currencyCode: String {
        if currencyCodes.contains(selectedCurrencyCode) { return selectedCurrencyCode }
        return currencyCodes.first ?? finance.overview?.currencyCode ?? "USD"
    }

    private var confirmedIncomeIDs: Set<String> {
        Set(finance.incomeOverview?.summaries
            .flatMap { $0.confirmedTransactions }
            .map(\.id) ?? [])
    }

    private var reviewIncomeIDs: Set<String> {
        Set(finance.incomeOverview?.summaries
            .flatMap { $0.needsReviewTransactions }
            .map(\.id) ?? [])
    }

    private var rangedTransactions: [FinanceTransaction] {
        let startDate = range.startDateString
        return transactions.filter { transaction in
            transaction.currencyCode.caseInsensitiveCompare(currencyCode) == .orderedSame
                && transaction.date >= startDate
                && matchesSearch(transaction)
        }
    }

    private var filteredTransactions: [FinanceTransaction] {
        rangedTransactions.filter { transaction in
            switch filter {
            case .all:
                true
            case .spending:
                transaction.direction == .outflow && transaction.countsAsSpending
            case .income:
                finance.incomeOverview != nil
                    && transaction.direction == .inflow
                    && confirmedIncomeIDs.contains(transaction.id)
            case .otherDeposits:
                finance.incomeOverview != nil
                    && transaction.direction == .inflow
                    && !transaction.isPaymentOrTransfer
                    && !confirmedIncomeIDs.contains(transaction.id)
            }
        }
    }

    private var transactionMonths: [FinanceTransactionMonth] {
        let grouped = Dictionary(grouping: filteredTransactions) { String($0.date.prefix(7)) }
        return grouped.keys.sorted(by: >).map { month in
            FinanceTransactionMonth(id: month, transactions: grouped[month] ?? [])
        }
    }

    private var postedSpent: Double {
        rangedTransactions
            .filter { !$0.pending && $0.direction == .outflow && $0.countsAsSpending }
            .reduce(0) { $0 + $1.amount }
    }

    private var postedIncome: Double? {
        guard finance.incomeOverview != nil else { return nil }
        return rangedTransactions
            .filter { !$0.pending && $0.direction == .inflow && confirmedIncomeIDs.contains($0.id) }
            .reduce(0) { $0 + $1.amount }
    }

    private var otherDeposits: Double? {
        guard finance.incomeOverview != nil else { return nil }
        return rangedTransactions
            .filter {
                !$0.pending
                    && $0.direction == .inflow
                    && !$0.isPaymentOrTransfer
                    && !confirmedIncomeIDs.contains($0.id)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private var topMerchants: [FinanceMerchantSpend] {
        var groups: [String: FinanceMerchantSpend] = [:]
        for transaction in rangedTransactions
        where !transaction.pending && transaction.direction == .outflow && transaction.countsAsSpending {
            let key = FinanceMerchantSpend.normalizedKey(transaction.displayName)
            guard !key.isEmpty else { continue }
            var merchant = groups[key] ?? FinanceMerchantSpend(
                id: key,
                name: transaction.displayName,
                amount: 0,
                count: 0,
                lastDate: transaction.date
            )
            merchant.amount += transaction.amount
            merchant.count += 1
            if transaction.date > merchant.lastDate {
                merchant.lastDate = transaction.date
                merchant.name = transaction.displayName
            }
            groups[key] = merchant
        }
        return groups.values.sorted {
            $0.amount > $1.amount || ($0.amount == $1.amount && $0.name < $1.name)
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                if transactions.isEmpty {
                    Text("No transactions are available yet. Plaid may still be preparing the first sync.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                } else {
                    controls
                    summary
                    merchantSection

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionHeader(title: filter.sectionTitle)
                        Text("\(filteredTransactions.count) transaction\(filteredTransactions.count == 1 ? "" : "s") in \(range.label.lowercased())")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)

                        if filteredTransactions.isEmpty {
                            Text("No transactions match these filters.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface()
                        } else {
                            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                ForEach(transactionMonths) { month in
                                    Text(FinanceTransactionDate.monthLabel(month.id))
                                        .sectionLabel()
                                        .padding(.horizontal, AppTheme.Spacing.xs)
                                    VStack(spacing: 0) {
                                        ForEach(Array(month.transactions.enumerated()), id: \.element.id) { index, transaction in
                                            FinanceTransactionRow(
                                                transaction: transaction,
                                                badge: badge(for: transaction)
                                            )
                                            if index < month.transactions.count - 1 {
                                                Divider().overlay(AppTheme.separator)
                                            }
                                        }
                                    }
                                    .cardSurface(padding: 0)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Merchant, app, or category")
        .refreshable {
            await finance.load(showLoading: false, forceRefresh: true)
        }
        .task {
            if finance.incomeOverview == nil, finance.isConnected {
                await finance.loadIncome(showLoading: false)
            }
        }
        .onAppear {
            if !currencyCodes.contains(selectedCurrencyCode) {
                selectedCurrencyCode = currencyCodes.first ?? ""
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSACTION HISTORY").sectionLabel()
                    Text("Actual income is kept separate from transfers and other deposits.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                if currencyCodes.count > 1 {
                    Menu {
                        ForEach(currencyCodes, id: \.self) { code in
                            Button(code) { selectedCurrencyCode = code }
                        }
                    } label: {
                        Text(currencyCode).font(.subheadline.weight(.semibold))
                    }
                }
            }

            Picker("History range", selection: $range) {
                ForEach(FinanceTransactionRange.allCases) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Transaction type", selection: $filter) {
                ForEach(FinanceTransactionFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .cardSurface()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("\(range.label.uppercased()) TOTALS").sectionLabel()
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                FinanceTransactionMetric(
                    title: "Actual income",
                    amount: postedIncome,
                    currencyCode: currencyCode,
                    tint: AppTheme.success
                )
                FinanceTransactionMetric(
                    title: "Spent",
                    amount: postedSpent,
                    currencyCode: currencyCode,
                    tint: AppTheme.primaryText
                )
                FinanceTransactionMetric(
                    title: "Other deposits",
                    amount: otherDeposits,
                    currencyCode: currencyCode,
                    tint: AppTheme.warning
                )
            }
            if let postedIncome {
                Divider().overlay(AppTheme.separator)
                HStack {
                    Label(
                        "Earned minus spent",
                        systemImage: postedIncome >= postedSpent ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(money(postedIncome - postedSpent))
                        .font(.headline)
                        .foregroundStyle(postedIncome >= postedSpent ? AppTheme.success : AppTheme.coral)
                        .monospacedDigit()
                }
            } else {
                Label("Income classification is still loading.", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var merchantSection: some View {
        if !topMerchants.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Top apps & merchants")
                Text("Combined posted spending for each merchant in \(range.label.lowercased()).")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                VStack(spacing: 0) {
                    ForEach(Array(topMerchants.enumerated()), id: \.element.id) { index, merchant in
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "storefront")
                                .font(.caption.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .background(AppTheme.secondarySurface, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(merchant.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(merchant.count) charge\(merchant.count == 1 ? "" : "s") · latest \(FinanceTransactionDate.shortDate(merchant.lastDate))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer(minLength: AppTheme.Spacing.sm)
                            Text(money(merchant.amount))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(AppTheme.Spacing.lg)
                        if index < topMerchants.count - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    private func matchesSearch(_ transaction: FinanceTransaction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [transaction.displayName, transaction.name, transaction.category, transaction.displayCategory]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func badge(for transaction: FinanceTransaction) -> FinanceTransactionBadge? {
        guard !transaction.isPaymentOrTransfer else { return nil }
        guard transaction.direction == .inflow, finance.incomeOverview != nil else { return nil }
        if confirmedIncomeIDs.contains(transaction.id) {
            return FinanceTransactionBadge(text: "Income", tint: AppTheme.success)
        }
        if reviewIncomeIDs.contains(transaction.id) {
            return FinanceTransactionBadge(text: "Review", tint: AppTheme.warning)
        }
        return FinanceTransactionBadge(text: "Deposit", tint: AppTheme.secondaryText)
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }
}

private enum FinanceTransactionRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }
    var label: String {
        switch self {
        case .oneMonth: "Last month"
        case .threeMonths: "Last 3 months"
        case .sixMonths: "Last 6 months"
        case .oneYear: "Last 12 months"
        }
    }
    var shortLabel: String {
        switch self {
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        }
    }
    var startDateString: String {
        let value: Date
        switch self {
        case .oneMonth:
            value = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        case .threeMonths:
            value = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
        case .sixMonths:
            value = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
        case .oneYear:
            value = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        }
        return FinanceTransactionDate.dateOnly(value)
    }
}

private enum FinanceTransactionFilter: String, CaseIterable, Identifiable {
    case all
    case spending
    case income
    case otherDeposits

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .spending: "Spent"
        case .income: "Income"
        case .otherDeposits: "Deposits"
        }
    }
    var sectionTitle: String {
        switch self {
        case .all: "All activity"
        case .spending: "Spending"
        case .income: "Actual income"
        case .otherDeposits: "Other deposits"
        }
    }
}

private struct FinanceTransactionMonth: Identifiable {
    var id: String
    var transactions: [FinanceTransaction]
}

private struct FinanceMerchantSpend: Identifiable {
    var id: String
    var name: String
    var amount: Double
    var count: Int
    var lastDate: String

    static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(
                of: "^(sq \\*|tst\\*|paypal \\*|google \\*|apple\\.com/bill\\s*)",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\b[0-9]{4,}\\b", with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct FinanceTransactionMetric: View {
    var title: String
    var amount: Double?
    var currencyCode: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
            Text(amount.map {
                $0.formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
            } ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FinanceTransactionBadge {
    var text: String
    var tint: Color
}

private struct FinanceInstitutionDetailView: View {
    @EnvironmentObject private var finance: FinanceRepository

    var institution: FinanceInstitution
    var initialOverview: FinanceOverview

    private var overview: FinanceOverview {
        guard case .loaded(let latest) = finance.state,
              latest.institutions.contains(where: { $0.id == institution.id }) else {
            return initialOverview
        }
        return latest
    }

    private var displayedInstitution: FinanceInstitution {
        overview.institutions.first(where: { $0.id == institution.id }) ?? institution
    }

    private var accounts: [FinanceAccount] {
        overview.accounts(for: displayedInstitution)
    }

    private var transactions: [FinanceTransaction] {
        overview.transactions(for: displayedInstitution)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                institutionHeader
                accountSections
                activitySection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle(displayedInstitution.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await finance.load(showLoading: false, forceRefresh: true)
        }
    }

    private var institutionHeader: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            FinanceInstitutionMark(name: displayedInstitution.name, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayedInstitution.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("\(accounts.count) connected account\(accounts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                if displayedInstitution.needsAttention {
                    Label("Connection needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .cardSurface()
    }

    private var accountSections: some View {
        let bankAccounts = accounts.filter { $0.group == .bank }
        let creditCards = accounts.filter { $0.group == .creditCards }
        let otherAccounts = accounts.filter { $0.group == .other }

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Accounts at \(displayedInstitution.name)")
            FinanceAccountsBox(
                group: .bank,
                accounts: bankAccounts,
                overview: overview,
                linksToInstitution: false
            )
            FinanceAccountsBox(
                group: .creditCards,
                accounts: creditCards,
                overview: overview,
                linksToInstitution: false
            )
            if !otherAccounts.isEmpty {
                FinanceAccountsBox(
                    group: .other,
                    accounts: otherAccounts,
                    overview: overview,
                    linksToInstitution: false
                )
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "\(displayedInstitution.name) activity")
            if transactions.isEmpty {
                Text("No recent transactions are available for this institution yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.prefix(30).enumerated()), id: \.element.id) { index, transaction in
                        FinanceTransactionRow(transaction: transaction)
                        if index < min(transactions.count, 30) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }
}

/// Compact institution artwork. Owner-supplied marks are used where bundled;
/// neutral initials remain the fallback for institutions without an approved
/// local asset.
private struct FinanceInstitutionMark: View {
    var name: String
    var size: CGFloat

    private var brand: FinanceInstitutionBrand {
        FinanceInstitutionBrand(institutionName: name)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(backgroundColor)

            mark
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if let assetName = brand.officialLogoAssetName {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size * officialLogoScale, height: size * officialLogoScale)
        } else if brand == .bankOfAmerica {
            Text("BOA")
                .font(.system(size: size * 0.22, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(foregroundColor)
        } else {
            Text(shortMark)
                .font(.system(size: size * fontScale, weight: .black, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(foregroundColor)
        }
    }

    private var officialLogoScale: CGFloat {
        switch brand {
        case .americanExpress: 0.76
        case .chase: 0.76
        case .discover: 0.84
        default: 0
        }
    }

    private var shortMark: String {
        switch brand {
        case .wellsFargo: "WF"
        case .citi: "citi"
        case .capitalOne: "C1"
        case .usBank: "US"
        case .pnc: "PNC"
        case .truist: "T"
        case .ally: "ally"
        case .sofi: "SoFi"
        case .fidelity: "F"
        case .schwab: "SCH"
        case .tdBank: "TD"
        case .navyFederal: "NFCU"
        case .fifthThird: "5/3"
        case .citizens: "C"
        case .paypal: "P"
        case .venmo: "V"
        case .generic: initials
        case .chase, .americanExpress, .discover, .bankOfAmerica: ""
        }
    }

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var fontScale: CGFloat {
        shortMark.count > 3 ? 0.17 : 0.23
    }

    private var backgroundColor: Color {
        switch brand {
        case .chase, .americanExpress, .discover: Color(light: 0xFFFFFF, dark: 0xF4F4F6)
        case .bankOfAmerica: Color(hex: 0xE31837)
        case .wellsFargo: Color(hex: 0xD71E28)
        case .citi: Color(hex: 0x056DAE)
        case .capitalOne: Color(hex: 0x004977)
        case .usBank: Color(hex: 0x0C2074)
        case .pnc: Color(hex: 0xF58025)
        case .truist: Color(hex: 0x2E1A47)
        case .ally: Color(hex: 0x5B2D82)
        case .sofi: Color(hex: 0x00A6A6)
        case .fidelity: Color(hex: 0x368727)
        case .schwab: Color(hex: 0x00A0DF)
        case .tdBank: Color(hex: 0x2EAB40)
        case .navyFederal: Color(hex: 0x003B70)
        case .fifthThird: Color(hex: 0x005EB8)
        case .citizens: Color(hex: 0x008555)
        case .paypal: Color(hex: 0x003087)
        case .venmo: Color(hex: 0x008CFF)
        case .generic: AppTheme.secondarySurface
        }
    }

    private var foregroundColor: Color {
        switch brand {
        case .wellsFargo: Color(hex: 0xFFCD41)
        case .generic: AppTheme.primaryText
        default: .white
        }
    }

    private var borderColor: Color {
        brand.officialLogoAssetName != nil || brand == .generic ? AppTheme.border : .clear
    }
}

private struct FinanceTransactionRow: View {
    var transaction: FinanceTransaction
    var badge: FinanceTransactionBadge? = nil

    private var displayedBadge: FinanceTransactionBadge? {
        if let badge { return badge }
        switch transaction.resolvedNature {
        case .creditCardPayment:
            return FinanceTransactionBadge(text: "Card payment", tint: AppTheme.info)
        case .accountTransfer:
            return FinanceTransactionBadge(text: "Transfer", tint: AppTheme.secondaryText)
        case .loanPayment:
            return FinanceTransactionBadge(text: "Debt payment", tint: AppTheme.warning)
        case .refund:
            return FinanceTransactionBadge(text: "Refund", tint: AppTheme.success)
        case .purchase, .income, .other:
            return nil
        }
    }

    private var isNeutralMovement: Bool { transaction.isPaymentOrTransfer }

    private var iconName: String {
        if isNeutralMovement { return "arrow.left.arrow.right" }
        return transaction.direction == .inflow ? "arrow.down.left" : "arrow.up.right"
    }

    private var directionTint: Color {
        if isNeutralMovement { return AppTheme.secondaryText }
        return transaction.direction == .inflow ? AppTheme.success : AppTheme.secondaryText
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(directionTint)
                .frame(width: 32, height: 32)
                .background(AppTheme.secondarySurface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(transaction.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if transaction.pending { Tag(text: "Pending", tint: AppTheme.warning) }
                    if let displayedBadge {
                        Tag(text: displayedBadge.text, tint: displayedBadge.tint)
                    }
                }
                Text([transaction.displayCategory, transaction.date].joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text("\(transaction.direction == .inflow ? "+" : "−")\(transaction.amount.formatted(.currency(code: transaction.currencyCode).precision(.fractionLength(0...2))))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    isNeutralMovement
                        ? AppTheme.secondaryText
                        : (transaction.direction == .inflow ? AppTheme.success : AppTheme.primaryText)
                )
                .monospacedDigit()
        }
        .padding(AppTheme.Spacing.lg)
    }
}

private struct FinanceRecurringPaymentRow: View {
    var payment: FinanceRecurringPayment

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 34, height: 34)
                .background(AppTheme.secondarySurface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(payment.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    if !payment.isConfirmed {
                        Tag(text: "Review", tint: AppTheme.warning)
                    }
                }
                if payment.isConfirmed {
                    HStack(spacing: 5) {
                        Text(payment.cadence.label)
                        if payment.isVariable { Text("· Variable") }
                        if let nextExpectedDate = payment.nextExpectedDate {
                            Text("· \(FinanceDateLabel.expected(nextExpectedDate))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                } else {
                    Text("Possible subscription · not counted in monthly total")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                if let spent = payment.spentLast12Months {
                    let count = payment.chargesLast12Months ?? payment.occurrences
                    Text("\(count) \(count == 1 ? "charge" : "charges") · \(money(spent)) in 12 months")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(payment.isVariable ? "~" : "")\(money(payment.amount))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
                if !payment.isConfirmed {
                    Text("last charge")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                } else if payment.cadence != .monthly {
                    Text("\(money(payment.monthlyAmount))/mo")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
    }

    private var systemImage: String {
        let category = payment.category?.lowercased() ?? ""
        if category.contains("subscription") { return "arrow.triangle.2.circlepath" }
        if category.contains("entertainment") { return "play.rectangle" }
        if category.contains("utilit") { return "bolt" }
        if category.contains("telecommunication") { return "antenna.radiowaves.left.and.right" }
        if category.contains("insurance") { return "shield" }
        if category.contains("loan") { return "creditcard" }
        return "repeat"
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: payment.currencyCode).precision(.fractionLength(0...2)))
    }
}

private struct RecurringPaymentsView: View {
    @EnvironmentObject private var finance: FinanceRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                content
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await finance.load(showLoading: false, forceRefresh: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch finance.state {
        case .loaded(let overview):
            let payments = overview.detectedRecurringPayments
            let confirmed = overview.confirmedRecurringPayments
            let possible = overview.possibleSubscriptions
            if payments.isEmpty {
                InfoStateView(
                    systemImage: "repeat",
                    title: "No recurring payments detected",
                    message: "Orbit uses merchant knowledge and repeated posted charges. Pull to refresh after more activity arrives."
                )
                .cardSurface()
            } else {
                recurringSummary(overview, confirmed: confirmed, possible: possible)
                if !confirmed.isEmpty {
                    paymentList(title: "Expected payments", payments: confirmed)
                }
                if !possible.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        paymentList(title: "Subscriptions to review", payments: possible)
                        Label(
                            "These match a subscription merchant, but Orbit needs more posting history before counting them as monthly commitments.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                detectionNote
            }
        case .loading, .idle:
            LoadingStateView(message: "Finding recurring payments…")
                .cardSurface()
        case .failed(let message):
            InfoStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load recurring payments",
                message: message,
                actionTitle: "Try again"
            ) {
                Task { await finance.load(forceRefresh: true) }
            }
            .cardSurface()
        case .empty, .disconnected:
            InfoStateView(
                systemImage: "building.columns",
                title: "Connect a financial account",
                message: "Recurring payments are detected from the posted transactions in your connected accounts."
            )
            .cardSurface()
        }
    }

    private func recurringSummary(
        _ overview: FinanceOverview,
        confirmed: [FinanceRecurringPayment],
        possible: [FinanceRecurringPayment]
    ) -> some View {
        let monthly = overview.detectedMonthlyRecurringTotal
        let spendingShare = overview.adjustedMonthlyOutflow > 0
            ? monthly / overview.adjustedMonthlyOutflow
            : 0
        let actualLast12Months = confirmed.compactMap(\.spentLast12Months).reduce(0, +)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("RECURRING ESTIMATE").sectionLabel()
            HStack(alignment: .firstTextBaseline) {
                Text(money(monthly, code: overview.currencyCode))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .minimumScaleFactor(0.7)
                Text("/ month")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
            }
            Divider().overlay(AppTheme.separator)
            HStack {
                summaryValue("\(confirmed.count)", label: "Confirmed")
                if !possible.isEmpty {
                    Spacer()
                    summaryValue("\(possible.count)", label: "To review")
                }
                Spacer()
                summaryValue(money(monthly * 12, code: overview.currencyCode), label: "Yearly pace")
                if overview.adjustedMonthlyOutflow > 0, possible.isEmpty {
                    Spacer()
                    summaryValue(
                        spendingShare.formatted(.percent.precision(.fractionLength(0))),
                        label: "Of spending"
                    )
                }
            }
            if actualLast12Months > 0 {
                Divider().overlay(AppTheme.separator)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Actually paid in the last 12 months")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("Across all detected recurring apps and merchants")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    Spacer()
                    Text(money(actualLast12Months, code: overview.currencyCode))
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .monospacedDigit()
                }
            }
        }
        .cardSurface()
    }

    private func paymentList(
        title: String,
        payments: [FinanceRecurringPayment]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                    FinanceRecurringPaymentRow(payment: payment)
                    if index < payments.count - 1 {
                        Divider().overlay(AppTheme.separator)
                    }
                }
            }
            .cardSurface(padding: 0)
        }
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var detectionNote: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("How estimates work", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Confirmed payments use timing and amount consistency. Merchant-based suggestions stay separate until more history arrives, and never enter the monthly total. Future dates remain estimates.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private func money(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }
}

private enum FinanceDateLabel {
    static func expected(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case Int.min ..< 0:
            return target.formatted(.dateTime.month(.abbreviated).day())
        case 0:
            return "Expected today"
        case 1:
            return "Expected tomorrow"
        case 2...14:
            return "Expected in \(days) days"
        default:
            return "Expected \(target.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private enum FinanceTransactionDate {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func dateOnly(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func monthLabel(_ value: String) -> String {
        guard let date = monthFormatter.date(from: value) else { return value }
        return date.formatted(.dateTime.month(.wide).year())
    }

    static func shortDate(_ value: String) -> String {
        guard let date = dateFormatter.date(from: value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

#if DEBUG
private struct FinanceDashboardDesignPreview: View {
    @State private var period: FinanceSpendingPeriod = .thisMonth
    @State private var selectedCategoryID: String?

    private let overview = FinanceDashboardPreviewData.overview

    private var analysis: FinanceSpendingAnalysis {
        FinanceSpendingAnalysis.make(overview: overview, period: period)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    FinancePositionCard(overview: overview)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppTheme.Spacing.md
                    ) {
                        FinanceMetricCard(
                            title: "This month in",
                            value: money(overview.adjustedMonthlyInflow),
                            systemImage: "arrow.down.left",
                            tint: AppTheme.success
                        )
                        FinanceMetricCard(
                            title: "This month spent",
                            value: money(overview.adjustedMonthlyOutflow),
                            systemImage: "arrow.up.right",
                            tint: AppTheme.coral
                        )
                    }
                    FinanceSmartInsightCard(overview: overview, spending: analysis)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionHeader(title: "Spending breakdown", actionTitle: "See all") {}
                        FinanceSpendingDashboardCard(
                            analysis: analysis,
                            selectedCategoryID: $selectedCategoryID,
                            period: $period
                        )
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Finance")
        }
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: overview.currencyCode).precision(.fractionLength(0...2)))
    }
}

private struct FinanceSpendingDesignPreview: View {
    @State private var period: FinanceSpendingPeriod = .thisMonth
    @State private var selectedCategoryID: String?

    private let overview = FinanceDashboardPreviewData.overview

    private var analysis: FinanceSpendingAnalysis {
        FinanceSpendingAnalysis.make(overview: overview, period: period)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SectionHeader(title: "Spending breakdown", actionTitle: "See all") {}
                    FinanceSpendingDashboardCard(
                        analysis: analysis,
                        selectedCategoryID: $selectedCategoryID,
                        period: $period
                    )
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Finance")
        }
    }
}

private enum FinanceDashboardPreviewData {
    static var overview: FinanceOverview {
        let date = FinanceTransactionDate.dateOnly(.now)
        let transactions = [
            transaction("rent", "Parkside Apartments", "Rent And Utilities", 950, date),
            transaction("groceries", "Whole Foods Market", "Food And Drink", 242.18, date),
            transaction("dinner", "Saffron Kitchen", "Food And Drink", 86.40, date),
            transaction("shopping", "Target", "General Merchandise", 219.34, date),
            transaction("transport", "Shell", "Transportation", 146.22, date),
            transaction("utilities", "Duke Energy", "Rent And Utilities", 198.10, date),
            transaction("streaming", "Streamflix", "Entertainment", 61.97, date),
            transaction("personal", "The Barber", "Personal Care", 49, date)
        ]
        let monthlyOutflow = transactions.reduce(0) { $0 + $1.amount }
        return FinanceOverview(
            institutions: [
                FinanceInstitution(id: "chase", name: "Chase", accountCount: 2, needsAttention: false),
                FinanceInstitution(id: "amex", name: "American Express", accountCount: 1, needsAttention: false)
            ],
            accounts: [],
            recentTransactions: transactions,
            monthlyInflow: 4_800,
            monthlyOutflow: monthlyOutflow,
            totalCash: 7_342.68,
            totalCreditBalance: 1_240.32,
            totalInvestments: 12_850.40,
            recurringPayments: [
                FinanceRecurringPayment(
                    id: "streamflix",
                    name: "Streamflix",
                    category: "Entertainment",
                    amount: 18.99,
                    monthlyAmount: 18.99,
                    currencyCode: "USD",
                    cadence: .monthly,
                    lastChargeDate: date,
                    nextExpectedDate: nil,
                    occurrences: 8,
                    chargesLast12Months: 8,
                    spentLast12Months: 151.92,
                    isVariable: false,
                    confidence: 0.98
                )
            ],
            monthlyRecurringTotal: 263.44,
            spendingByCategory: nil,
            currencyCode: "USD",
            lastUpdatedAt: nil
        )
    }

    private static func transaction(
        _ id: String,
        _ merchant: String,
        _ category: String,
        _ amount: Double,
        _ date: String
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountID: "checking",
            date: date,
            name: merchant,
            merchantName: merchant,
            category: category,
            amount: amount,
            direction: .outflow,
            pending: false,
            currencyCode: "USD"
        )
    }
}
#endif

#Preview {
    let app = PreviewSupport.appState()
    return FinanceView()
        .environmentObject(app)
        .environmentObject(app.finance)
}

#Preview("Finance dashboard design") {
    FinanceDashboardDesignPreview()
}

#Preview("Finance spending breakdown") {
    FinanceSpendingDesignPreview()
}

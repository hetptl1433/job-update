import AuthenticationServices
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
                else { await finance.load(showLoading: false) }
            }
            .task {
                await finance.load()
                if finance.hasPendingHostedLink { await finance.resumeHostedLinkIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      authenticationSession == nil,
                      finance.hasPendingHostedLink else { return }
                Task { await finance.resumeHostedLinkIfNeeded() }
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
        case .empty, .idle:
            connectState
        case .failed(let message):
            InfoStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load Finance",
                message: message,
                actionTitle: "Try again"
            ) { Task { await finance.load() } }
            .cardSurface()
            connectButton(title: "Connect an institution")
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            summaryGrid(overview)
            incomeDestination
            cashFlowCard(overview)
            accountsSection(overview)
            transactionsSection(overview)
            institutionsSection(overview)
            privacyCard
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

    private func summaryGrid(_ overview: FinanceOverview) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppTheme.Spacing.md
        ) {
            FinanceMetricCard(
                title: "Cash",
                value: money(overview.totalCash, code: overview.currencyCode),
                systemImage: "banknote",
                tint: AppTheme.success
            )
            FinanceMetricCard(
                title: "Cards owed",
                value: money(overview.totalCreditBalance, code: overview.currencyCode),
                systemImage: "creditcard",
                tint: AppTheme.coral
            )
            FinanceMetricCard(
                title: "This month in",
                value: money(overview.monthlyInflow, code: overview.currencyCode),
                systemImage: "arrow.down.left",
                tint: AppTheme.success
            )
            FinanceMetricCard(
                title: "This month out",
                value: money(overview.monthlyOutflow, code: overview.currencyCode),
                systemImage: "arrow.up.right",
                tint: AppTheme.coral
            )
        }
    }

    private func cashFlowCard(_ overview: FinanceOverview) -> some View {
        let total = max(overview.monthlyInflow + overview.monthlyOutflow, 1)
        let inflowShare = overview.monthlyInflow / total
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTHLY CASH FLOW").sectionLabel()
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
                Label("Inflow", systemImage: "circle.fill").foregroundStyle(AppTheme.success)
                Spacer()
                Label("Outflow", systemImage: "circle.fill").foregroundStyle(AppTheme.coral)
            }
            .font(.caption2)
        }
        .cardSurface()
    }

    private func accountsSection(_ overview: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Accounts", actionTitle: "Add", action: beginConnection)
            VStack(spacing: 0) {
                ForEach(Array(overview.accounts.enumerated()), id: \.element.id) { index, account in
                    FinanceAccountRow(account: account)
                    if index < overview.accounts.count - 1 { Divider().overlay(AppTheme.separator) }
                }
            }
            .cardSurface(padding: 0)
        }
    }

    private func transactionsSection(_ overview: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Recent activity")
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
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "building.columns")
                            .frame(width: 32, height: 32)
                            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(institution.name).font(.subheadline.weight(.semibold))
                            Text("\(institution.accountCount) account\(institution.accountCount == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        if institution.needsAttention {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.warning)
                        }
                        Menu {
                            Button("Disconnect", role: .destructive) {
                                institutionToDisconnect = institution
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
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

private struct FinanceAccountRow: View {
    var account: FinanceAccount

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: account.kind.systemImage)
                .font(.subheadline)
                .frame(width: 34, height: 34)
                .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
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
        }
        .padding(AppTheme.Spacing.lg)
    }
}

private struct FinanceTransactionRow: View {
    var transaction: FinanceTransaction

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: transaction.direction == .inflow ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(transaction.direction == .inflow ? AppTheme.success : AppTheme.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppTheme.secondarySurface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(transaction.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if transaction.pending { Tag(text: "Pending", tint: AppTheme.warning) }
                }
                Text([transaction.category, transaction.date].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text("\(transaction.direction == .inflow ? "+" : "−")\(transaction.amount.formatted(.currency(code: transaction.currencyCode).precision(.fractionLength(0...2))))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(transaction.direction == .inflow ? AppTheme.success : AppTheme.primaryText)
                .monospacedDigit()
        }
        .padding(AppTheme.Spacing.lg)
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return FinanceView()
        .environmentObject(app)
        .environmentObject(app.finance)
}

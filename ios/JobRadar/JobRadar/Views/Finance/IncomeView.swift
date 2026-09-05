import Charts
import SwiftUI

/// Dedicated earned-income experience. Orbit combines hard accounting guards,
/// provider evidence, and an optional AI organization pass; user corrections
/// always remain the final authority.
struct IncomeView: View {
    @EnvironmentObject private var finance: FinanceRepository
    @AppStorage("orbit.ai.financeAutoOrganizeEnabled") private var autoOrganizeWithAI = false

    @State private var selectedCurrencyCode = ""
    @State private var historyRange = IncomeHistoryRange.oneYear
    @State private var transactionToReview: IncomeTransaction?
    @State private var goal = StoredIncomeGoal.zero
    @State private var showingGoalEditor = false
    @State private var showingOtherDeposits = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                content
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await finance.loadIncome(showLoading: false) }
        .task {
            guard finance.isConnected else { return }
            if finance.incomeOverview == nil { await finance.loadIncome() }
        }
        .sheet(item: $transactionToReview) { transaction in
            IncomeClassificationSheet(transaction: transaction)
                .environmentObject(finance)
        }
        .sheet(isPresented: $showingGoalEditor) {
            IncomeGoalEditor(currencyCode: activeCurrencyCode, goal: goal) { updated in
                goal = updated
                IncomeGoalStorage.save(updated, currencyCode: activeCurrencyCode)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch finance.incomeState {
        case .loading:
            LoadingStateView(message: "Separating income from other deposits…")
                .cardSurface()
            calculatorDestination(currencyCode: "USD")
        case .loaded(let overview):
            if overview.summaries.isEmpty {
                emptyContent
            } else {
                loadedContent(overview)
            }
        case .empty, .idle:
            emptyContent
        case .failed(let message):
            InfoStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load Income",
                message: message,
                actionTitle: "Try again"
            ) { Task { await finance.loadIncome() } }
            .cardSurface()
            calculatorDestination(currencyCode: activeCurrencyCode)
        case .disconnected:
            InfoStateView(
                systemImage: "building.columns",
                title: "Connect an account for observed income",
                message: "Connected deposits are classified on Orbit's secure backend. You can still use the gross-income calculator without connecting a bank."
            )
            .cardSurface()
            calculatorDestination(currencyCode: activeCurrencyCode)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            InfoStateView(
                systemImage: "dollarsign.arrow.circlepath",
                title: "No observed income yet",
                message: "Orbit found no posted, confirmed income in the connected history. Transfers, refunds and uncertain deposits are not silently counted."
            )
            .cardSurface()
            calculatorDestination(currencyCode: activeCurrencyCode)
        }
    }

    private func loadedContent(_ overview: IncomeOverview) -> some View {
        let summary = selectedSummary(in: overview)
        return Group {
            if let summary {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    aiOrganizationStatus(summary)
                    currencySelector(overview)
                    observedSummary(summary)
                    reviewSection(summary)
                    sourcesSection(summary)
                    confirmedDepositsSection(summary)
                    excludedDepositsSection(summary)
                    historySection(summary)
                    projectionSection(summary)
                    goalSection(summary)
                    calculatorDestination(currencyCode: summary.currencyCode)
                    coverageFooter(summary, lastUpdatedAt: overview.lastUpdatedAt)
                }
            } else {
                emptyContent
            }
        }
        .onAppear {
            let selected = overview.summaries.contains { $0.currencyCode == selectedCurrencyCode }
            if !selected, let first = overview.summaries.first {
                selectCurrency(first.currencyCode)
            }
        }
    }

    @ViewBuilder
    private func aiOrganizationStatus(_ summary: IncomeCurrencySummary) -> some View {
        if finance.isAutoSortingIncome {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Orbit AI is sorting new deposits")
                        .font(.subheadline.weight(.semibold))
                    Text("Income, transfers, and other deposits will move into place automatically.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }
            .cardSurface(padding: AppTheme.Spacing.md)
        } else if let message = finance.incomeOrganizationMessage {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.brand)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: AppTheme.Spacing.sm)
                if autoOrganizeWithAI, !summary.needsReviewTransactions.isEmpty {
                    Button("Retry") { finance.organizeIncomeWithAI(force: true) }
                        .font(.caption.weight(.semibold))
                }
            }
            .cardSurface(padding: AppTheme.Spacing.md)
        }
    }

    @ViewBuilder
    private func currencySelector(_ overview: IncomeOverview) -> some View {
        if overview.summaries.count > 1 {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENCY").sectionLabel()
                    Text("Currencies are kept separate—no hidden exchange rate.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Menu {
                    ForEach(overview.summaries, id: \.currencyCode) { summary in
                        Button {
                            selectCurrency(summary.currencyCode)
                        } label: {
                            if summary.currencyCode == selectedCurrencyCode {
                                Label(summary.currencyCode, systemImage: "checkmark")
                            } else {
                                Text(summary.currencyCode)
                            }
                        }
                    }
                } label: {
                    Label(activeCurrencyCode, systemImage: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                }
            }
            .cardSurface()
        }
    }

    private func observedSummary(_ summary: IncomeCurrencySummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("THIS MONTH · OBSERVED NET DEPOSITS").sectionLabel()
                Text(incomeMoney(summary.thisMonth.confirmed, code: summary.currencyCode))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Posted transactions classified as income")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Divider().overlay(AppTheme.separator)

            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                IncomeCompactMetric(
                    title: "Last month",
                    value: incomeMoney(summary.lastMonth.confirmed, code: summary.currencyCode)
                )
                IncomeCompactMetric(
                    title: "Change",
                    value: changeText(summary),
                    detail: changePercentText(summary.changePercent),
                    tint: changeTint(summary.changeAmount)
                )
            }

            Divider().overlay(AppTheme.separator)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: AppTheme.Spacing.md
            ) {
                IncomeCompactMetric(
                    title: "Last 12 months",
                    value: incomeMoney(summary.confirmedLast12Months, code: summary.currencyCode),
                    detail: "Confirmed deposits"
                )
                IncomeCompactMetric(
                    title: "Year to date",
                    value: incomeMoney(summary.yearToDate, code: summary.currencyCode)
                )
                IncomeCompactMetric(
                    title: "Monthly avg.",
                    value: incomeMoney(summary.averageMonthly, code: summary.currencyCode)
                )
                IncomeCompactMetric(
                    title: "Est. annual",
                    value: summary.estimatedAnnual.map { incomeMoney($0, code: summary.currencyCode) } ?? "—",
                    detail: summary.estimatedAnnual == nil ? "Not enough history" : "Projected"
                )
            }

            if summary.thisMonth.pending > 0 || summary.thisMonth.needsReview > 0 {
                Divider().overlay(AppTheme.separator)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if summary.thisMonth.pending > 0 {
                        IncomeStatusLine(
                            title: "Pending income",
                            value: incomeMoney(summary.thisMonth.pending, code: summary.currencyCode),
                            detail: "Not included until posted",
                            systemImage: "clock",
                            tint: AppTheme.secondaryText
                        )
                    }
                    if summary.thisMonth.needsReview > 0 {
                        IncomeStatusLine(
                            title: "Needs review",
                            value: incomeMoney(summary.thisMonth.needsReview, code: summary.currencyCode),
                            detail: "Not included in confirmed income",
                            systemImage: "questionmark.circle",
                            tint: AppTheme.warning
                        )
                    }
                }
            }
        }
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func reviewSection(_ summary: IncomeCurrencySummary) -> some View {
        if !summary.needsReviewTransactions.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Needs review")
                Text("These deposits are excluded from confirmed income until you decide what they are.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                VStack(spacing: 0) {
                    ForEach(Array(summary.needsReviewTransactions.enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            transactionToReview = transaction
                        } label: {
                            IncomeReviewRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        if index < summary.needsReviewTransactions.count - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
                .animation(.snappy(duration: 0.32), value: summary.needsReviewTransactions.map(\.id))
            }
        }
    }

    @ViewBuilder
    private func sourcesSection(_ summary: IncomeCurrencySummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Income sources")
            if summary.sources.isEmpty {
                Text("No recurring income source has enough confirmed history yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summary.sources.enumerated()), id: \.element.id) { index, source in
                        IncomeSourceRow(source: source, currencyCode: summary.currencyCode)
                        if index < summary.sources.count - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
            }
        }
    }

    @ViewBuilder
    private func confirmedDepositsSection(_ summary: IncomeCurrencySummary) -> some View {
        if !summary.confirmedTransactions.isEmpty {
            let visible = Array(summary.confirmedTransactions.prefix(20))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Sorted income deposits")
                Text("Tap any deposit to correct Orbit and move it out of Income. Your choice is remembered for matching future deposits.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            transactionToReview = transaction
                        } label: {
                            IncomeReviewRow(transaction: transaction, isConfirmed: true)
                        }
                        .buttonStyle(.plain)
                        if index < visible.count - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .cardSurface(padding: 0)
                .animation(.snappy(duration: 0.32), value: visible.map(\.id))

                if summary.confirmedTransactions.count > visible.count {
                    Text("Showing the 20 most recent income deposits. All deposits remain available in Transactions.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func excludedDepositsSection(_ summary: IncomeCurrencySummary) -> some View {
        let transactions = summary.excludedTransactions ?? []
        if !transactions.isEmpty {
            DisclosureGroup(isExpanded: $showingOtherDeposits) {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.prefix(20).enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            transactionToReview = transaction
                        } label: {
                            IncomeReviewRow(transaction: transaction, isExcluded: true)
                        }
                        .buttonStyle(.plain)
                        if index < min(transactions.count, 20) - 1 {
                            Divider().overlay(AppTheme.separator)
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
                .animation(.snappy(duration: 0.32), value: transactions.map(\.id))
            } label: {
                HStack {
                    Label("Other deposits", systemImage: "tray")
                    Spacer()
                    Text("\(transactions.count)")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .font(.subheadline.weight(.semibold))
            }
            .tint(AppTheme.primaryText)
            .cardSurface()
        }
    }

    private func historySection(_ summary: IncomeCurrencySummary) -> some View {
        let history = filteredHistory(summary.history)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").sectionLabel()
                Spacer()
                Picker("History range", selection: $historyRange) {
                    ForEach(IncomeHistoryRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.menu)
            }

            if history.isEmpty {
                Text("No posted income history is available for this range.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Chart(history) { month in
                        BarMark(
                            x: .value("Month", month.month),
                            y: .value("Confirmed income", decimalDouble(month.confirmed))
                        )
                        .foregroundStyle(AppTheme.brand)
                        .cornerRadius(3)

                        if month.needsReview > 0 {
                            PointMark(
                                x: .value("Month", month.month),
                                y: .value("Needs review", decimalDouble(month.confirmed + month.needsReview))
                            )
                            .foregroundStyle(AppTheme.warning)
                            .symbolSize(28)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let month = value.as(String.self) {
                                    Text(shortMonth(month))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(AppTheme.separator)
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(abbreviatedMoney(number, code: summary.currencyCode))
                                }
                            }
                        }
                    }
                    .frame(height: 190)
                    .accessibilityLabel("Confirmed income history")

                    HStack(spacing: AppTheme.Spacing.lg) {
                        Label("Confirmed", systemImage: "square.fill")
                            .foregroundStyle(AppTheme.primaryText)
                        if history.contains(where: { $0.needsReview > 0 }) {
                            Label("Needs review", systemImage: "circle.fill")
                                .foregroundStyle(AppTheme.warning)
                        }
                    }
                    .font(.caption2)
                }
                .cardSurface()
            }
        }
    }

    @ViewBuilder
    private func projectionSection(_ summary: IncomeCurrencySummary) -> some View {
        if summary.projectedMonthEnd != nil || summary.projectedYearEnd != nil || !summary.expectedPaychecks.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Expected")
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if summary.projectedMonthEnd != nil || summary.projectedYearEnd != nil {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            if let month = summary.projectedMonthEnd {
                                IncomeCompactMetric(
                                    title: "Projected month-end",
                                    value: incomeMoney(month, code: summary.currencyCode)
                                )
                            }
                            if let year = summary.projectedYearEnd {
                                IncomeCompactMetric(
                                    title: "Projected year-end",
                                    value: incomeMoney(year, code: summary.currencyCode)
                                )
                            }
                        }
                    }

                    ForEach(summary.expectedPaychecks, id: \.sourceID) { paycheck in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paycheck.sourceName)
                                    .font(.subheadline.weight(.semibold))
                                Text("Expected around \(displayDate(paycheck.date))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Text("≈\(incomeMoney(paycheck.estimatedAmount, code: summary.currencyCode))")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }

                    Label(
                        "Projections are estimates from recurring posted deposits, not guaranteed earnings.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .cardSurface()
            }
        }
    }

    private func goalSection(_ summary: IncomeCurrencySummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(
                title: "Income goals",
                actionTitle: goal.hasGoal ? "Edit" : "Set goal",
                action: { showingGoalEditor = true }
            )
            if goal.hasGoal {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if goal.monthly > 0 {
                        IncomeGoalProgress(
                            title: "Monthly observed income",
                            current: summary.thisMonth.confirmed,
                            target: goal.monthly,
                            currencyCode: summary.currencyCode
                        )
                    }
                    if goal.annual > 0 {
                        IncomeGoalProgress(
                            title: "Annual observed income",
                            current: summary.yearToDate,
                            target: goal.annual,
                            currencyCode: summary.currencyCode
                        )
                    }
                    Text("Goals use confirmed deposited income. Gross calculator estimates stay separate.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .cardSurface()
            } else {
                Button { showingGoalEditor = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Set a calm monthly or annual target")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("Progress is based only on confirmed deposits.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .cardSurface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func calculatorDestination(currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Plan")
            NavigationLink {
                IncomeCalculatorView(currencyCode: currencyCode)
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "function")
                        .font(.title3.weight(.medium))
                        .frame(width: 40, height: 40)
                        .background(
                            AppTheme.secondarySurface,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Income calculator")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text("Combine hourly, salary, monthly and one-time gross income.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func coverageFooter(_ summary: IncomeCurrencySummary, lastUpdatedAt: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let coverage = summary.coverage {
                if let startDate = coverage.startDate {
                    Label(
                        "Connected records \(displayDate(startDate))–\(displayDate(coverage.endDate)) · \(coverage.completeMonths) complete month\(coverage.completeMonths == 1 ? "" : "s")",
                        systemImage: "calendar"
                    )
                } else {
                    Label("Account connected; no posted transaction history yet.", systemImage: "calendar")
                }
            }
            if let lastUpdatedAt {
                Label("Updated \(displayTimestamp(lastUpdatedAt))", systemImage: "arrow.clockwise")
            }
            Label(
                "Totals cover connected accounts only. Gross salary, taxes and deductions are not inferred from deposits.",
                systemImage: "lock.shield"
            )
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var activeCurrencyCode: String {
        selectedCurrencyCode.isEmpty ? "USD" : selectedCurrencyCode
    }

    private func selectedSummary(in overview: IncomeOverview) -> IncomeCurrencySummary? {
        overview.summaries.first { $0.currencyCode == selectedCurrencyCode } ?? overview.summaries.first
    }

    private func selectCurrency(_ code: String) {
        selectedCurrencyCode = code
        goal = IncomeGoalStorage.load(currencyCode: code)
    }

    private func filteredHistory(_ history: [IncomeHistoryMonth]) -> [IncomeHistoryMonth] {
        switch historyRange {
        case .sixMonths:
            return Array(history.suffix(6))
        case .yearToDate:
            let year = String(Calendar.current.component(.year, from: .now))
            return history.filter { $0.month.hasPrefix(year) }
        case .oneYear:
            return history
        }
    }

    private func changeText(_ summary: IncomeCurrencySummary) -> String {
        guard let change = summary.changeAmount else { return "—" }
        return signedIncomeMoney(change, code: summary.currencyCode)
    }
}

private enum IncomeHistoryRange: String, CaseIterable, Identifiable {
    case sixMonths
    case yearToDate
    case oneYear

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sixMonths: "6 months"
        case .yearToDate: "YTD"
        case .oneYear: "12 months"
        }
    }
}

private struct IncomeCompactMetric: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = AppTheme.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IncomeStatusLine: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct IncomeReviewRow: View {
    let transaction: IncomeTransaction
    var isConfirmed = false
    var isExcluded = false

    private var tint: Color {
        if isConfirmed { return AppTheme.success }
        if isExcluded { return AppTheme.secondaryText }
        return AppTheme.warning
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: transaction.pending ? "clock" : (isConfirmed ? "arrow.down.left" : (isExcluded ? "tray" : "questionmark")))
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(transaction.merchantName ?? transaction.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    if transaction.decisionSource == .ai {
                        Tag(text: "AI", tint: AppTheme.brand)
                    } else if transaction.decisionSource == .user || transaction.userConfirmed {
                        Tag(text: "You", tint: AppTheme.primaryText)
                    } else if transaction.decisionSource == .provider {
                        Tag(text: "Bank", tint: AppTheme.info)
                    } else if transaction.decisionSource == .deterministicRule {
                        Tag(text: "Orbit", tint: AppTheme.secondaryText)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(incomeMoney(transaction.amount, code: transaction.currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
                Text(displayDate(transaction.date))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(AppTheme.Spacing.lg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            isConfirmed
                ? "Opens controls to move this deposit out of Income"
                : (isExcluded ? "Opens controls to move this deposit into Income" : "Review whether this deposit is income")
        )
    }

    private var detail: String {
        if isConfirmed {
            let source = transaction.sourceName ?? transaction.classificationReason
            return source?.isEmpty == false ? source! : "Sorted as income"
        }
        if isExcluded {
            return transaction.classificationReason ?? "Sorted as another deposit"
        }
        return transaction.classificationReason ?? "Orbit could not confirm this deposit"
    }
}

private struct IncomeSourceRow: View {
    let source: IncomeSource
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: source.type == .interest || source.type == .dividend ? "percent" : "building.2")
                    .font(.subheadline)
                    .frame(width: 34, height: 34)
                    .background(
                        AppTheme.secondarySurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(source.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if source.userConfirmed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.primaryText)
                                .accessibilityLabel("User confirmed")
                        } else if source.decisionSource == .ai {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(AppTheme.brand)
                                .accessibilityLabel("Sorted by AI")
                        } else if source.decisionSource == .provider {
                            Image(systemName: "building.columns.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.info)
                                .accessibilityLabel("Sorted from bank data")
                        }
                    }
                    Text("\(source.type.label) · \(source.frequency.label)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(incomeMoney(source.thisMonth, code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("this month")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            HStack(spacing: AppTheme.Spacing.lg) {
                IncomeCompactMetric(
                    title: "Avg. deposit",
                    value: incomeMoney(source.averagePayment, code: currencyCode)
                )
                IncomeCompactMetric(
                    title: "Avg. monthly",
                    value: incomeMoney(source.averageMonthly, code: currencyCode)
                )
                IncomeCompactMetric(
                    title: "YTD",
                    value: incomeMoney(source.yearToDate, code: currencyCode)
                )
            }

            if let next = source.nextExpectedPaymentDate, source.active {
                Label("Next expected around \(displayDate(next))", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .accessibilityElement(children: .contain)
    }
}

struct IncomeClassificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var finance: FinanceRepository

    let transaction: IncomeTransaction

    @State private var sourceName: String
    @State private var sourceType: IncomeType
    @State private var saving = false
    @State private var isAnalyzing = false
    @State private var aiSuggestion: IncomeAISuggestion?
    @State private var errorMessage: String?
    @State private var analysisTask: Task<Void, Never>?

    private var hasOpenAIKey: Bool {
        !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    init(transaction: IncomeTransaction) {
        self.transaction = transaction
        _sourceName = State(initialValue: transaction.sourceName ?? transaction.merchantName ?? transaction.name)
        _sourceType = State(initialValue: transaction.sourceType ?? .other)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deposit") {
                    LabeledContent("Description", value: transaction.merchantName ?? transaction.name)
                    LabeledContent("Amount", value: incomeMoney(transaction.amount, code: transaction.currencyCode))
                    LabeledContent("Date", value: displayDate(transaction.date))
                    LabeledContent("Status", value: transaction.pending ? "Pending" : "Posted")
                    if transaction.classification == .income || transaction.classification == .notIncome {
                        LabeledContent("Current group") {
                            HStack(spacing: 5) {
                                Text(transaction.classification == .income ? "Income" : "Other deposit")
                                if transaction.decisionSource == .ai {
                                    Tag(text: "AI sorted", tint: AppTheme.brand)
                                } else if transaction.decisionSource == .user || transaction.userConfirmed {
                                    Tag(text: "You", tint: AppTheme.primaryText)
                                } else if transaction.decisionSource == .provider {
                                    Tag(text: "Bank", tint: AppTheme.info)
                                } else if transaction.decisionSource == .deterministicRule {
                                    Tag(text: "Orbit", tint: AppTheme.secondaryText)
                                }
                            }
                        }
                    }
                }

                if let reason = transaction.classificationReason, !reason.isEmpty {
                    Section(reasonSectionTitle) {
                        Text(classificationReasonLabel(reason)).foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Section {
                    if hasOpenAIKey {
                        Button {
                            analyzeWithAI()
                        } label: {
                            HStack {
                                Label(aiSuggestion == nil ? "Get AI suggestion" : "Refresh AI suggestion", systemImage: "sparkles")
                                Spacer()
                                if isAnalyzing { ProgressView() }
                            }
                        }
                        .disabled(saving || isAnalyzing)
                    } else {
                        Label("Connect OpenAI processing in Settings first.", systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    if let suggestion = aiSuggestion {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack {
                                Text("Suggestion")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Tag(text: suggestionLabel(suggestion), tint: suggestionTint(suggestion))
                            }
                            Text(suggestion.reason)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text("\(suggestion.confidence.formatted(.percent.precision(.fractionLength(0)))) confidence · Review before saving")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                } header: {
                    Text("Optional AI suggestion")
                } footer: {
                    Text("Ask Orbit to analyze a compact deposit summary, then choose below. Automatic sorting is controlled from Finance, and your manual choice always wins.")
                }

                Section("If this is income") {
                    TextField("Income source name", text: $sourceName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Picker("Income type", selection: $sourceType) {
                        ForEach(IncomeType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    Text("Orbit will use this exact normalized deposit description to classify similar future payments for your account.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Section {
                    Button {
                        save(classification: .income)
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() } else { Text(transaction.classification == .income ? "Keep in Income" : "Move to Income") }
                            Spacer()
                        }
                    }
                    .disabled(saving || sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(transaction.classification == .income ? "Move out of Income" : "Keep as Other Deposit") {
                        save(classification: .notIncome)
                    }
                    .disabled(saving)
                } footer: {
                    Text("Not-income decisions keep transfers, refunds and other deposits out of earnings totals.")
                }
            }
            .navigationTitle("Organize deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        analysisTask?.cancel()
                        dismiss()
                    }
                    .disabled(saving)
                }
            }
            .alert("Organize deposit", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
        .onDisappear {
            analysisTask?.cancel()
        }
    }

    private func analyzeWithAI() {
        guard !isAnalyzing,
              let key = KeychainStore.get(KeychainKeys.openAIKey),
              !key.isEmpty else { return }
        isAnalyzing = true
        analysisTask = Task {
            do {
                let suggestion = try await IncomeIntelligence(apiKey: key).suggest(
                    transaction: transaction,
                    transactionHistory: finance.overview?.recentTransactions ?? []
                )
                try Task.checkCancellation()
                aiSuggestion = suggestion
                if suggestion.classification == .income {
                    sourceName = suggestion.sourceName
                    sourceType = suggestion.sourceType
                }
            } catch is CancellationError {
                // A manual choice or dismissal always takes precedence.
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
            analysisTask = nil
        }
    }

    private func suggestionLabel(_ suggestion: IncomeAISuggestion) -> String {
        switch suggestion.classification {
        case .income: "Likely income"
        case .notIncome: "Likely not income"
        case .needsReview: "Still uncertain"
        }
    }

    private func suggestionTint(_ suggestion: IncomeAISuggestion) -> Color {
        switch suggestion.classification {
        case .income: AppTheme.success
        case .notIncome: AppTheme.secondaryText
        case .needsReview: AppTheme.warning
        }
    }

    private func classificationReasonLabel(_ value: String) -> String {
        switch value {
        case "providerIncomeCategory": "Your financial provider categorized this deposit as income."
        case "userOverride": "You chose how this deposit should be organized."
        case "userDescriptorRule": "This matches a deposit description you organized before."
        case "ownAccountTransfer": "Orbit matched this to a transfer between your own accounts."
        case "transferCategory": "Your financial provider categorized this as a transfer."
        case "loanProceeds": "This looks like loan proceeds rather than earned income."
        case "reimbursement": "This looks like a reimbursement rather than earned income."
        case "refundOrReversal": "This looks like a refund or reversed charge rather than earned income."
        case "ambiguousTransfer": "A similar transfer could not be matched with enough confidence."
        case "peerToPeer": "Peer-to-peer deposits are not treated as earnings without confirmation."
        case "incomeKeyword": "The description looks income-related, but the provider did not confirm it."
        case "unrecognizedInflow": "This deposit does not have enough evidence to count as income."
        default: value
        }
    }

    private var reasonSectionTitle: String {
        if transaction.classification == .income { return "Why this is in Income" }
        if transaction.classification == .notIncome { return "Why this is outside Income" }
        return "Why this needs review"
    }

    private func save(classification: IncomeClassification) {
        guard !saving else { return }
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        let submittedSourceName = sourceName
        let submittedSourceType = sourceType
        saving = true
        Task {
            do {
                try await finance.classifyIncomeTransaction(
                    id: transaction.id,
                    as: classification,
                    sourceName: submittedSourceName,
                    sourceType: submittedSourceType
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                saving = false
            }
        }
    }
}

private struct IncomeGoalProgress: View {
    let title: String
    let current: Decimal
    let target: Decimal
    let currencyCode: String

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return max(0, decimalDouble(current / target))
    }

    private var remaining: Decimal { max(0, target - current) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(incomeMoney(current, code: currencyCode)) of \(incomeMoney(target, code: currencyCode))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: min(fraction, 1))
                .tint(AppTheme.brand)
            Text(remaining > 0 ? "\(incomeMoney(remaining, code: currencyCode)) remaining" : "Goal reached")
                .font(.caption2)
                .foregroundStyle(remaining > 0 ? AppTheme.secondaryText : AppTheme.success)
        }
    }
}

private struct StoredIncomeGoal: Codable, Hashable {
    var monthly: Decimal
    var annual: Decimal

    static let zero = StoredIncomeGoal(monthly: 0, annual: 0)
    var hasGoal: Bool { monthly > 0 || annual > 0 }
}

private enum IncomeGoalStorage {
    private static let prefix = "orbit.finance.incomeGoal.v1."

    static func load(currencyCode: String, defaults: UserDefaults = .standard) -> StoredIncomeGoal {
        guard let data = defaults.data(forKey: prefix + currencyCode.uppercased()),
              let value = try? JSONDecoder().decode(StoredIncomeGoal.self, from: data) else {
            return .zero
        }
        return StoredIncomeGoal(monthly: max(0, value.monthly), annual: max(0, value.annual))
    }

    static func save(
        _ goal: StoredIncomeGoal,
        currencyCode: String,
        defaults: UserDefaults = .standard
    ) {
        let safe = StoredIncomeGoal(monthly: max(0, goal.monthly), annual: max(0, goal.annual))
        guard let data = try? JSONEncoder().encode(safe) else { return }
        defaults.set(data, forKey: prefix + currencyCode.uppercased())
    }
}

private struct IncomeGoalEditor: View {
    @Environment(\.dismiss) private var dismiss

    let currencyCode: String
    let onSave: (StoredIncomeGoal) -> Void

    @State private var monthly: Double
    @State private var annual: Double

    init(currencyCode: String, goal: StoredIncomeGoal, onSave: @escaping (StoredIncomeGoal) -> Void) {
        self.currencyCode = currencyCode
        self.onSave = onSave
        _monthly = State(initialValue: decimalDouble(goal.monthly))
        _annual = State(initialValue: decimalDouble(goal.annual))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Monthly") {
                        TextField("0", value: $monthly, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Annual") {
                        TextField("0", value: $annual, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Observed net deposit goals")
                } footer: {
                    Text("Amounts are in \(currencyCode). Enter 0 to remove a goal. Goals never change classified income totals.")
                }
            }
            .navigationTitle("Income goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(StoredIncomeGoal(
                            monthly: decimal(max(0, monthly)),
                            annual: decimal(max(0, annual))
                        ))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private func incomeMoney(_ amount: Decimal, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(code) \(amount)"
}

private func signedIncomeMoney(_ amount: Decimal, code: String) -> String {
    if amount > 0 { return "+" + incomeMoney(amount, code: code) }
    return incomeMoney(amount, code: code)
}

private func changePercentText(_ percent: Decimal?) -> String? {
    guard let percent else { return "No comparable percentage" }
    let number = NSDecimalNumber(decimal: percent).doubleValue
    let prefix = number > 0 ? "+" : ""
    return "\(prefix)\(number.formatted(.number.precision(.fractionLength(1))))%"
}

private func changeTint(_ amount: Decimal?) -> Color {
    guard let amount else { return AppTheme.primaryText }
    if amount > 0 { return AppTheme.success }
    if amount < 0 { return AppTheme.destructive }
    return AppTheme.primaryText
}

private func decimalDouble(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}

private func decimal(_ value: Double) -> Decimal {
    guard value.isFinite, value > 0 else { return 0 }
    return Decimal(value)
}

private func displayDate(_ value: String) -> String {
    guard let date = incomeDateFormatter.date(from: value) else { return value }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
}

private func displayTimestamp(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(.relative(presentation: .named))
}

private func shortMonth(_ value: String) -> String {
    guard let date = incomeMonthFormatter.date(from: value) else { return value }
    return date.formatted(.dateTime.month(.abbreviated))
}

private func abbreviatedMoney(_ value: Double, code: String) -> String {
    if #available(iOS 18.0, *) {
        return value.formatted(
            .currency(code: code)
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    let units: [(threshold: Double, suffix: String)] = [
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K")
    ]

    let magnitude = abs(value)
    let unit = units.first { magnitude >= $0.threshold }
    let scaled = unit.map { value / $0.threshold } ?? value

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = 1
    formatter.minimumFractionDigits = 0
    let formatted = formatter.string(from: NSNumber(value: scaled)) ?? "\(code) \(scaled)"
    return formatted + (unit?.suffix ?? "")
}

private let incomeDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let incomeMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM"
    return formatter
}()

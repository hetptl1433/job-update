import SwiftUI

/// Deterministic gross-income and optional take-home estimator. Connected bank
/// deposits are intentionally not used here: user-entered compensation is gross
/// planning data, while the Income page reports observed net deposits.
struct IncomeCalculatorView: View {
    let currencyCode: String

    @State private var sources = [IncomeCalculatorDraft.primary]
    @State private var showingTakeHome = false
    @State private var takeHome = IncomeTakeHomeDraft()

    private var calculation: IncomeGrossBreakdown {
        IncomeCalculator.calculate(sources: sources.map(\.model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                basisNotice
                sourcesSection
                grossSummary
                equivalentsSection
                takeHomeSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Income Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var basisNotice: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: "function")
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Gross planning estimate")
                    .font(.subheadline.weight(.semibold))
                Text("These user-entered estimates stay separate from actual deposited income. Calculations are deterministic and do not use AI.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Income sources").sectionLabel()
                Spacer()
                Button {
                    withAnimation { sources.append(.additional(index: sources.count + 1)) }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                }
            }

            ForEach($sources) { $source in
                IncomeCalculatorSourceCard(
                    source: $source,
                    currencyCode: currencyCode,
                    canDelete: sources.count > 1,
                    onDelete: { removeSource(source.id) }
                )
            }
        }
    }

    private var grossSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("COMBINED ESTIMATED GROSS").sectionLabel()
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                CalculatorHeroMetric(
                    title: "Monthly",
                    value: calculatorMoney(calculation.monthly, code: currencyCode)
                )
                CalculatorHeroMetric(
                    title: "Annual",
                    value: calculatorMoney(calculation.annual, code: currencyCode)
                )
            }
            let disabledCount = sources.filter { !$0.isEnabled }.count
            if disabledCount > 0 {
                Label(
                    "\(disabledCount) disabled source\(disabledCount == 1 ? "" : "s") excluded",
                    systemImage: "minus.circle"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private var equivalentsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Pay equivalents")
            VStack(spacing: 0) {
                CalculatorEquivalentRow(title: "Monthly", detail: "12 periods / year", amount: calculation.monthly, code: currencyCode)
                Divider().overlay(AppTheme.separator)
                CalculatorEquivalentRow(title: "Biweekly", detail: "26 periods / year", amount: calculation.biweekly, code: currencyCode)
                Divider().overlay(AppTheme.separator)
                CalculatorEquivalentRow(title: "Semimonthly", detail: "24 periods / year", amount: calculation.semimonthly, code: currencyCode)
                Divider().overlay(AppTheme.separator)
                CalculatorEquivalentRow(title: "Weekly", detail: "52 periods / year", amount: calculation.weekly, code: currencyCode)
                Divider().overlay(AppTheme.separator)
                CalculatorEquivalentRow(title: "Daily", detail: "260 workdays / year", amount: calculation.daily, code: currencyCode)
                Divider().overlay(AppTheme.separator)
                CalculatorEquivalentRow(title: "Hourly", detail: "2,080 hours / year", amount: calculation.hourly, code: currencyCode)
            }
            .cardSurface(padding: 0)
        }
    }

    private var takeHomeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Button {
                withAnimation { showingTakeHome.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Optional take-home estimate")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text("Use only tax and deduction rates you enter")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: showingTakeHome ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingTakeHome {
                IncomeTakeHomeEditor(
                    draft: $takeHome,
                    grossAnnual: calculation.annual,
                    currencyCode: currencyCode
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardSurface()
    }

    private func removeSource(_ id: UUID) {
        guard sources.count > 1 else { return }
        withAnimation { sources.removeAll { $0.id == id } }
    }
}

private struct IncomeCalculatorDraft: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var mode: IncomeCalculationMode
    var amount: Double
    var hoursPerWeek: Double
    var weeksPerYear: Double
    var annualBonus: Double
    var additionalAnnualIncome: Double
    var isEnabled: Bool

    static let primary = IncomeCalculatorDraft(
        name: "Primary income",
        mode: .hourly,
        amount: 0,
        hoursPerWeek: 40,
        weeksPerYear: 52,
        annualBonus: 0,
        additionalAnnualIncome: 0,
        isEnabled: true
    )

    static func additional(index: Int) -> IncomeCalculatorDraft {
        IncomeCalculatorDraft(
            name: "Income source \(index)",
            mode: .hourly,
            amount: 0,
            hoursPerWeek: 0,
            weeksPerYear: 52,
            annualBonus: 0,
            additionalAnnualIncome: 0,
            isEnabled: true
        )
    }

    var model: IncomeCalculatorSource {
        IncomeCalculatorSource(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            amount: calculatorDecimal(amount),
            hoursPerWeek: calculatorDecimal(hoursPerWeek),
            weeksPerYear: calculatorDecimal(weeksPerYear),
            annualBonus: calculatorDecimal(annualBonus),
            additionalAnnualIncome: calculatorDecimal(additionalAnnualIncome),
            isEnabled: isEnabled
        )
    }

    var hasInvalidInput: Bool {
        [amount, hoursPerWeek, weeksPerYear, annualBonus, additionalAnnualIncome]
            .contains { !$0.isFinite || $0 < 0 }
    }
}

private struct IncomeCalculatorSourceCard: View {
    @Binding var source: IncomeCalculatorDraft
    let currencyCode: String
    let canDelete: Bool
    let onDelete: () -> Void

    @State private var showingExtras = false

    private var sourceAnnual: Decimal {
        IncomeCalculator.annualGross(for: source.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                Toggle("", isOn: $source.isEnabled)
                    .labelsHidden()
                    .tint(AppTheme.brand)
                    .accessibilityLabel("Include \(source.name)")
                TextField("Source name", text: $source.name)
                    .font(.headline)
                    .textInputAutocapitalization(.words)
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove \(source.name)")
                }
            }

            Picker("Income format", selection: $source.mode) {
                ForEach(IncomeCalculationMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)

            VStack(spacing: AppTheme.Spacing.md) {
                CalculatorNumberField(
                    title: amountTitle,
                    unit: currencyCode,
                    value: $source.amount
                )

                if source.mode == .hourly {
                    CalculatorNumberField(title: "Hours / week", unit: "hours", value: $source.hoursPerWeek)
                    CalculatorNumberField(title: "Weeks / year", unit: "weeks", value: $source.weeksPerYear)
                }
            }

            Button {
                withAnimation { showingExtras.toggle() }
            } label: {
                HStack {
                    Text(showingExtras ? "Hide bonus and additional income" : "Bonus and additional income")
                    Spacer()
                    Image(systemName: showingExtras ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            }
            .buttonStyle(.plain)

            if showingExtras {
                VStack(spacing: AppTheme.Spacing.md) {
                    CalculatorNumberField(
                        title: "Annual bonus",
                        unit: currencyCode,
                        value: $source.annualBonus
                    )
                    CalculatorNumberField(
                        title: "Other annual income",
                        unit: currencyCode,
                        value: $source.additionalAnnualIncome
                    )
                }
            }

            Divider().overlay(AppTheme.separator)

            HStack(alignment: .firstTextBaseline) {
                Text("Estimated annual gross")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(calculatorMoney(sourceAnnual, code: currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(source.isEnabled ? AppTheme.primaryText : AppTheme.tertiaryText)
                    .monospacedDigit()
            }

            if source.hasInvalidInput {
                Label("Negative or invalid entries are treated as zero.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .cardSurface()
        .opacity(source.isEnabled ? 1 : 0.62)
    }

    private var amountTitle: String {
        switch source.mode {
        case .hourly: "Hourly rate"
        case .annualSalary: "Annual salary"
        case .monthly: "Monthly amount"
        case .oneTime: "One-time amount"
        }
    }
}

private struct CalculatorNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: AppTheme.Spacing.md)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 70, idealWidth: 90, maxWidth: 120)
                .accessibilityLabel(title)
            Text(unit)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

private struct CalculatorHeroMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalculatorEquivalentRow: View {
    let title: String
    let detail: String
    let amount: Decimal
    let code: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(calculatorMoney(amount, code: code))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(AppTheme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

private struct IncomeTakeHomeDraft: Hashable {
    var state = ""
    var federalTaxPercent = 0.0
    var stateTaxPercent = 0.0
    var ficaPercent = 7.65
    var retirement401kPercent = 0.0
    var annualHealthInsurance = 0.0
    var annualOtherDeductions = 0.0
    var displayFrequency = TakeHomeDisplayFrequency.monthly

    func input(grossAnnual: Decimal) -> IncomeTakeHomeInput {
        IncomeTakeHomeInput(
            grossAnnual: grossAnnual,
            state: state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state,
            federalTaxPercent: calculatorDecimal(federalTaxPercent),
            stateTaxPercent: calculatorDecimal(stateTaxPercent),
            ficaPercent: calculatorDecimal(ficaPercent),
            retirement401kPercent: calculatorDecimal(retirement401kPercent),
            annualHealthInsurance: calculatorDecimal(annualHealthInsurance),
            annualOtherDeductions: calculatorDecimal(annualOtherDeductions)
        )
    }

    var hasOutOfRangeRate: Bool {
        [federalTaxPercent, stateTaxPercent, ficaPercent, retirement401kPercent]
            .contains { !$0.isFinite || $0 < 0 || $0 > 100 }
    }
}

private enum TakeHomeDisplayFrequency: String, CaseIterable, Identifiable {
    case annual
    case monthly
    case biweekly
    case semimonthly
    case weekly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .annual: "Annual"
        case .monthly: "Monthly"
        case .biweekly: "Biweekly"
        case .semimonthly: "Semimonthly"
        case .weekly: "Weekly"
        }
    }

    func value(from breakdown: IncomeGrossBreakdown) -> Decimal {
        switch self {
        case .annual: breakdown.annual
        case .monthly: breakdown.monthly
        case .biweekly: breakdown.biweekly
        case .semimonthly: breakdown.semimonthly
        case .weekly: breakdown.weekly
        }
    }
}

private struct IncomeTakeHomeEditor: View {
    @Binding var draft: IncomeTakeHomeDraft
    let grossAnnual: Decimal
    let currencyCode: String

    private var estimate: IncomeTakeHomeEstimate {
        IncomeTakeHomeCalculator.estimate(draft.input(grossAnnual: grossAnnual))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Divider().overlay(AppTheme.separator)

            TextField("State (informational)", text: $draft.state)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            VStack(spacing: AppTheme.Spacing.md) {
                CalculatorNumberField(title: "Federal tax", unit: "%", value: $draft.federalTaxPercent)
                CalculatorNumberField(title: "State tax", unit: "%", value: $draft.stateTaxPercent)
                CalculatorNumberField(title: "FICA", unit: "%", value: $draft.ficaPercent)
                CalculatorNumberField(title: "401(k)", unit: "%", value: $draft.retirement401kPercent)
                CalculatorNumberField(
                    title: "Health insurance / year",
                    unit: currencyCode,
                    value: $draft.annualHealthInsurance
                )
                CalculatorNumberField(
                    title: "Other deductions / year",
                    unit: currencyCode,
                    value: $draft.annualOtherDeductions
                )
            }

            if draft.hasOutOfRangeRate {
                Label("Rates outside 0–100% are safely clamped for the estimate.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }

            Divider().overlay(AppTheme.separator)

            Picker("Take-home period", selection: $draft.displayFrequency) {
                ForEach(TakeHomeDisplayFrequency.allCases) { frequency in
                    Text(frequency.label).tag(frequency)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("ESTIMATED \(draft.displayFrequency.label.uppercased()) TAKE-HOME").sectionLabel()
                Text(calculatorMoney(
                    draft.displayFrequency.value(from: estimate.takeHomeByFrequency),
                    code: currencyCode
                ))
                .font(.title2.weight(.bold))
                .monospacedDigit()

                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    IncomeTakeHomeMetric(
                        title: "Annual taxes",
                        value: calculatorMoney(estimate.estimatedTaxesAnnual, code: currencyCode)
                    )
                    IncomeTakeHomeMetric(
                        title: "Annual deductions",
                        value: calculatorMoney(estimate.estimatedDeductionsAnnual, code: currencyCode)
                    )
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                AppTheme.secondarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            )

            Label(
                "Estimate only. Orbit does not infer a state rate and this is not tax advice. Actual withholding and take-home pay may differ.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IncomeTakeHomeMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func calculatorDecimal(_ value: Double) -> Decimal {
    guard value.isFinite, value > 0 else { return 0 }
    return Decimal(value)
}

private func calculatorMoney(_ amount: Decimal, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(code) \(amount)"
}

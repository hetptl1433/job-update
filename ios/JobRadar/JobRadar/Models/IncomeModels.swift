import Foundation

// MARK: - Resilient wire enums

protocol IncomeFallbackStringEnum: RawRepresentable, Codable where RawValue == String {
    static var fallbackValue: Self { get }
}

extension IncomeFallbackStringEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = Self(rawValue: rawValue) ?? Self.fallbackValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum IncomeType: String, Codable, CaseIterable, Hashable, Sendable, IncomeFallbackStringEnum {
    case salary
    case hourly
    case contract
    case freelance
    case consulting
    case business
    case bonus
    case commission
    case interest
    case dividend
    case other

    static let fallbackValue = IncomeType.other

    var label: String {
        switch self {
        case .salary: "Salary"
        case .hourly: "Hourly"
        case .contract: "Contract"
        case .freelance: "Freelance"
        case .consulting: "Consulting"
        case .business: "Business"
        case .bonus: "Bonus"
        case .commission: "Commission"
        case .interest: "Interest"
        case .dividend: "Dividend"
        case .other: "Other"
        }
    }
}

enum PayFrequency: String, Codable, CaseIterable, Hashable, Sendable, IncomeFallbackStringEnum {
    case weekly
    case biweekly
    case semimonthly
    case monthly
    case irregular
    case oneTime

    static let fallbackValue = PayFrequency.irregular

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .semimonthly: "Semimonthly"
        case .monthly: "Monthly"
        case .irregular: "Irregular"
        case .oneTime: "One-time"
        }
    }
}

/// The server's classification vocabulary. Unknown values deliberately become
/// `needsReview` so an ambiguous deposit is never silently counted as income.
enum IncomeClassification: String, Codable, CaseIterable, Hashable, Sendable, IncomeFallbackStringEnum {
    case income
    case notIncome
    case needsReview

    static let fallbackValue = IncomeClassification.needsReview
}

enum IncomeTransactionDirection: String, Codable, Hashable, Sendable, IncomeFallbackStringEnum {
    case inflow
    case outflow
    case unknown

    static let fallbackValue = IncomeTransactionDirection.unknown
}

/// Makes gross, estimated net, and observed deposits impossible to label as
/// interchangeable values in calculator and presentation code.
enum IncomeAmountBasis: String, Codable, Hashable, Sendable, IncomeFallbackStringEnum {
    case gross
    case estimatedNet
    case observedNetDeposit

    static let fallbackValue = IncomeAmountBasis.observedNetDeposit
}

// MARK: - Backend read models

struct IncomeOverview: Codable, Hashable, Sendable {
    var summaries: [IncomeCurrencySummary]
    var lastUpdatedAt: String?
}

struct IncomeCurrencySummary: Identifiable, Codable, Hashable, Sendable {
    var currencyCode: String
    var basis: IncomeAmountBasis?
    var thisMonth: IncomeAmountBuckets
    var lastMonth: IncomeAmountBuckets
    var changeAmount: Decimal?
    var changePercent: Decimal?
    var yearToDate: Decimal
    var averageMonthly: Decimal
    var estimatedAnnual: Decimal?
    var sources: [IncomeSource]
    var history: [IncomeHistoryMonth]
    var confirmedTransactions: [IncomeTransaction]
    var needsReviewTransactions: [IncomeTransaction]
    var projectedMonthEnd: Decimal?
    var projectedYearEnd: Decimal?
    var expectedPaychecks: [IncomeExpectedPaycheck]
    var coverage: IncomeDataCoverage?

    var id: String { currencyCode }
    var amountBasis: IncomeAmountBasis { basis ?? .observedNetDeposit }
}

struct IncomeAmountBuckets: Codable, Hashable, Sendable {
    var confirmed: Decimal
    var pending: Decimal
    var needsReview: Decimal
}

struct IncomeSource: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var type: IncomeType
    var accountID: String
    var frequency: PayFrequency
    var averagePayment: Decimal
    var averageMonthly: Decimal
    var lastPaymentDate: String?
    var nextExpectedPaymentDate: String?
    var active: Bool
    var confidence: Double
    var userConfirmed: Bool
    var thisMonth: Decimal
    var yearToDate: Decimal
    var transactionCount: Int
    var basis: IncomeAmountBasis?

    var amountBasis: IncomeAmountBasis { basis ?? .observedNetDeposit }
}

struct IncomeHistoryMonth: Identifiable, Codable, Hashable, Sendable {
    var month: String
    var confirmed: Decimal
    var pending: Decimal
    var needsReview: Decimal

    var id: String { month }
}

struct IncomeTransaction: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var accountID: String
    var date: String
    var authorizedDate: String?
    var name: String
    var merchantName: String?
    var category: String?
    var amount: Decimal
    var direction: IncomeTransactionDirection
    var pending: Bool
    var currencyCode: String
    var sourceName: String?
    var sourceType: IncomeType?
    var confidence: Double
    var classificationReason: String?
    var userConfirmed: Bool
    var classification: IncomeClassification?
    var basis: IncomeAmountBasis?

    /// Transaction feeds generally expose deposited take-home pay, not gross
    /// compensation. This semantic is intentionally independent of confidence.
    var amountBasis: IncomeAmountBasis { basis ?? .observedNetDeposit }
}

struct IncomeExpectedPaycheck: Identifiable, Codable, Hashable, Sendable {
    var sourceID: String
    var sourceName: String
    var date: String
    var estimatedAmount: Decimal
    var confidence: Double

    var id: String { "\(sourceID)-\(date)" }
}

struct IncomeDataCoverage: Codable, Hashable, Sendable {
    /// Nil when an account is connected but no normalized transaction has
    /// posted yet. Decoding that honest state must not fail the whole page.
    var startDate: String?
    var endDate: String
    var completeMonths: Int
}

struct IncomeOverviewEnvelope: Codable, Hashable, Sendable {
    var data: IncomeOverview
}

/// Body for the transaction-classification endpoint. The endpoint accepts
/// `.income` and `.notIncome`; `.needsReview` remains a decode fallback and
/// should not be submitted as a user decision.
struct IncomeClassificationRequest: Codable, Hashable, Sendable {
    var classification: IncomeClassification
    var sourceName: String?
    var type: IncomeType?
    var asOfDate: String
    var timeZone: String

    init(
        classification: IncomeClassification,
        sourceName: String? = nil,
        type: IncomeType? = nil,
        asOfDate: String,
        timeZone: String
    ) {
        self.classification = classification
        self.sourceName = sourceName
        self.type = type
        self.asOfDate = asOfDate
        self.timeZone = timeZone
    }
}

struct IncomeClassificationResponse: Codable, Hashable, Sendable {
    var data: IncomeOverview
}

// MARK: - Gross income calculator

enum IncomeCalculationMode: String, Codable, CaseIterable, Hashable, Sendable, IncomeFallbackStringEnum {
    case hourly
    case annualSalary
    case monthly
    case oneTime

    /// A one-time fallback avoids accidentally annualizing an unknown saved
    /// mode as an hourly rate.
    static let fallbackValue = IncomeCalculationMode.oneTime

    var label: String {
        switch self {
        case .hourly: "Hourly"
        case .annualSalary: "Annual salary"
        case .monthly: "Monthly"
        case .oneTime: "One-time"
        }
    }
}

struct IncomeCalculatorSource: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var mode: IncomeCalculationMode
    /// Hourly rate, annual salary, monthly amount, or one-time amount according
    /// to `mode`.
    var amount: Decimal
    var hoursPerWeek: Decimal
    var weeksPerYear: Decimal
    var annualBonus: Decimal
    var additionalAnnualIncome: Decimal
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mode: IncomeCalculationMode,
        amount: Decimal,
        hoursPerWeek: Decimal = 40,
        weeksPerYear: Decimal = 52,
        annualBonus: Decimal = 0,
        additionalAnnualIncome: Decimal = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.amount = amount
        self.hoursPerWeek = hoursPerWeek
        self.weeksPerYear = weeksPerYear
        self.annualBonus = annualBonus
        self.additionalAnnualIncome = additionalAnnualIncome
        self.isEnabled = isEnabled
    }
}

struct IncomeGrossBreakdown: Codable, Hashable, Sendable {
    let basis: IncomeAmountBasis
    let annual: Decimal
    let monthly: Decimal
    let biweekly: Decimal
    let semimonthly: Decimal
    let weekly: Decimal
    let daily: Decimal
    let hourly: Decimal

    static let zero = IncomeGrossBreakdown(annual: 0)

    init(annual: Decimal, basis: IncomeAmountBasis = .gross) {
        let annual = IncomeDecimalMath.currency(annual)
        self.basis = basis
        self.annual = annual
        monthly = IncomeDecimalMath.currency(annual / 12)
        biweekly = IncomeDecimalMath.currency(annual / 26)
        semimonthly = IncomeDecimalMath.currency(annual / 24)
        weekly = IncomeDecimalMath.currency(annual / 52)
        daily = IncomeDecimalMath.currency(annual / 260)
        hourly = IncomeDecimalMath.currency(annual / 2_080)
    }
}

enum IncomeCalculator {
    static func calculate(sources: [IncomeCalculatorSource]) -> IncomeGrossBreakdown {
        let annual = sources.reduce(Decimal.zero) { runningTotal, source in
            guard source.isEnabled else { return runningTotal }
            return IncomeDecimalMath.nonnegative(runningTotal + annualGross(for: source))
        }

        return IncomeGrossBreakdown(annual: annual)
    }

    static func annualGross(for source: IncomeCalculatorSource) -> Decimal {
        guard source.isEnabled else { return 0 }

        let amount = IncomeDecimalMath.nonnegative(source.amount)
        let baseAnnual: Decimal

        switch source.mode {
        case .hourly:
            let hours = IncomeDecimalMath.nonnegative(source.hoursPerWeek)
            let weeks = IncomeDecimalMath.nonnegative(source.weeksPerYear)
            baseAnnual = IncomeDecimalMath.nonnegative(amount * hours * weeks)
        case .annualSalary:
            baseAnnual = amount
        case .monthly:
            baseAnnual = IncomeDecimalMath.nonnegative(amount * 12)
        case .oneTime:
            baseAnnual = amount
        }

        let bonus = IncomeDecimalMath.nonnegative(source.annualBonus)
        let additional = IncomeDecimalMath.nonnegative(source.additionalAnnualIncome)
        return IncomeDecimalMath.currency(baseAnnual + bonus + additional)
    }
}

// MARK: - Optional take-home estimator

struct IncomeTakeHomeInput: Codable, Hashable, Sendable {
    var grossAnnual: Decimal
    /// Informational only. No tax rate is inferred from the state.
    var state: String?
    var federalTaxPercent: Decimal
    var stateTaxPercent: Decimal
    var ficaPercent: Decimal
    var retirement401kPercent: Decimal
    var annualHealthInsurance: Decimal
    var annualOtherDeductions: Decimal

    init(
        grossAnnual: Decimal,
        state: String? = nil,
        federalTaxPercent: Decimal = 0,
        stateTaxPercent: Decimal = 0,
        ficaPercent: Decimal = 0,
        retirement401kPercent: Decimal = 0,
        annualHealthInsurance: Decimal = 0,
        annualOtherDeductions: Decimal = 0
    ) {
        self.grossAnnual = grossAnnual
        self.state = state
        self.federalTaxPercent = federalTaxPercent
        self.stateTaxPercent = stateTaxPercent
        self.ficaPercent = ficaPercent
        self.retirement401kPercent = retirement401kPercent
        self.annualHealthInsurance = annualHealthInsurance
        self.annualOtherDeductions = annualOtherDeductions
    }
}

struct IncomeTakeHomeEstimate: Codable, Hashable, Sendable {
    let basis: IncomeAmountBasis
    let grossAnnual: Decimal
    let estimatedTaxesAnnual: Decimal
    let estimatedDeductionsAnnual: Decimal
    let estimatedTakeHomeAnnual: Decimal
    let takeHomeByFrequency: IncomeGrossBreakdown

    var isEstimate: Bool { true }
}

enum IncomeTakeHomeCalculator {
    static func estimate(_ input: IncomeTakeHomeInput) -> IncomeTakeHomeEstimate {
        let gross = IncomeDecimalMath.currency(input.grossAnnual)

        let combinedTaxPercent = IncomeDecimalMath.percentage(
            IncomeDecimalMath.percentage(input.federalTaxPercent)
                + IncomeDecimalMath.percentage(input.stateTaxPercent)
                + IncomeDecimalMath.percentage(input.ficaPercent)
        )
        let taxes = min(
            gross,
            IncomeDecimalMath.currency(gross * combinedTaxPercent / 100)
        )

        let retirement = IncomeDecimalMath.currency(
            gross * IncomeDecimalMath.percentage(input.retirement401kPercent) / 100
        )
        let fixedDeductions = IncomeDecimalMath.nonnegative(input.annualHealthInsurance)
            + IncomeDecimalMath.nonnegative(input.annualOtherDeductions)
        let availableAfterTaxes = max(0, gross - taxes)
        let deductions = min(
            availableAfterTaxes,
            IncomeDecimalMath.currency(retirement + fixedDeductions)
        )
        let takeHome = IncomeDecimalMath.currency(gross - taxes - deductions)

        return IncomeTakeHomeEstimate(
            basis: .estimatedNet,
            grossAnnual: gross,
            estimatedTaxesAnnual: taxes,
            estimatedDeductionsAnnual: deductions,
            estimatedTakeHomeAnnual: takeHome,
            takeHomeByFrequency: IncomeGrossBreakdown(annual: takeHome, basis: .estimatedNet)
        )
    }
}

private enum IncomeDecimalMath {
    static func nonnegative(_ value: Decimal) -> Decimal {
        guard !value.isNaN, value > 0 else { return 0 }
        return value
    }

    static func percentage(_ value: Decimal) -> Decimal {
        min(nonnegative(value), 100)
    }

    static func currency(_ value: Decimal) -> Decimal {
        var value = nonnegative(value)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &value, 2, .plain)
        return nonnegative(rounded)
    }
}

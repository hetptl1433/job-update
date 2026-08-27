import Foundation

/// Typed destinations owned by Finance's navigation stack. Deep links, widgets,
/// and in-app links all route through this enum instead of scattering strings
/// through individual views.
enum FinanceRoute: String, Hashable, Codable {
    case income
    case recurring
    case transactions
}

/// Backend-normalized financial account categories. Plaid access tokens never
/// cross into these app-facing models.
enum FinanceAccountKind: String, Codable, CaseIterable, Hashable {
    case checking
    case savings
    case creditCard
    case investment
    case loan
    case other

    var label: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .investment: "Investment"
        case .loan: "Loan"
        case .other: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .creditCard: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "doc.text"
        case .other: "wallet.bifold"
        }
    }
}

/// The presentation group used throughout Finance. A credit-card balance is
/// debt, so it must never be visually combined with checking or savings cash.
enum FinanceAccountGroup: String, CaseIterable, Hashable {
    case bank
    case creditCards
    case other

    var title: String {
        switch self {
        case .bank: "Bank accounts"
        case .creditCards: "Credit cards"
        case .other: "Other accounts"
        }
    }

    var emptyMessage: String {
        switch self {
        case .bank: "No checking or savings accounts in this connection."
        case .creditCards: "No credit cards in this connection."
        case .other: "No investment, loan, or other accounts in this connection."
        }
    }

    var systemImage: String {
        switch self {
        case .bank: "building.columns"
        case .creditCards: "creditcard"
        case .other: "wallet.bifold"
        }
    }
}

extension FinanceAccount {
    var group: FinanceAccountGroup {
        switch kind {
        case .checking, .savings: .bank
        case .creditCard: .creditCards
        case .investment, .loan, .other: .other
        }
    }
}

/// Known institutions get purpose-built, code-native marks in the UI. Matching
/// is intentionally tolerant because Plaid institution display names can vary
/// (for example, "American Express" and "AMEX").
enum FinanceInstitutionBrand: String, CaseIterable, Hashable {
    case chase
    case americanExpress
    case discover
    case bankOfAmerica
    case wellsFargo
    case citi
    case capitalOne
    case usBank
    case pnc
    case truist
    case ally
    case sofi
    case fidelity
    case schwab
    case tdBank
    case navyFederal
    case fifthThird
    case citizens
    case paypal
    case venmo
    case generic

    init(institutionName: String) {
        let name = FinanceInstitutionName.normalized(institutionName)
        switch name {
        case let value where value.contains("americanexpress") || value.contains("amex"):
            self = .americanExpress
        case let value where value.contains("bankofamerica") || value.contains("bofa"):
            self = .bankOfAmerica
        case let value where value.contains("wellsfargo"):
            self = .wellsFargo
        case let value where value.contains("capitalone"):
            self = .capitalOne
        case let value where value.contains("usbank"):
            self = .usBank
        case let value where value.contains("charlesschwab") || value == "schwab":
            self = .schwab
        case let value where value.contains("tdbank"):
            self = .tdBank
        case let value where value.contains("navyfederal"):
            self = .navyFederal
        case let value where value.contains("fifththird") || value.contains("53bank"):
            self = .fifthThird
        case let value where value.contains("chase"):
            self = .chase
        case let value where value.contains("discover"):
            self = .discover
        case let value where value.contains("citi"):
            self = .citi
        case let value where value.contains("pnc"):
            self = .pnc
        case let value where value.contains("truist"):
            self = .truist
        case let value where value.contains("ally"):
            self = .ally
        case let value where value.contains("sofi"):
            self = .sofi
        case let value where value.contains("fidelity"):
            self = .fidelity
        case let value where value.contains("citizens"):
            self = .citizens
        case let value where value.contains("paypal"):
            self = .paypal
        case let value where value.contains("venmo"):
            self = .venmo
        default:
            self = .generic
        }
    }

    /// Exact owner-supplied marks bundled for the institutions whose compact
    /// symbols are legible at account-row sizes. Other institutions retain the
    /// neutral initials fallback until an approved asset is available.
    var officialLogoAssetName: String? {
        switch self {
        case .chase: "FinanceLogoChase"
        case .americanExpress: "FinanceLogoAmericanExpress"
        case .discover: "FinanceLogoDiscover"
        default: nil
        }
    }
}

enum FinanceInstitutionName {
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBrand = FinanceInstitutionBrand(institutionName: lhs)
        let rhsBrand = FinanceInstitutionBrand(institutionName: rhs)
        if lhsBrand != .generic, lhsBrand == rhsBrand { return true }
        return normalized(lhs) == normalized(rhs)
    }
}

struct FinanceLiability: Codable, Hashable {
    var minimumPayment: Double?
    var lastStatementBalance: Double?
    var nextPaymentDueDate: String?
}

struct FinanceAccount: Identifiable, Codable, Hashable {
    var id: String
    var itemID: String
    var institutionName: String
    var name: String
    var officialName: String?
    var mask: String?
    var kind: FinanceAccountKind
    var subtype: String?
    var currentBalance: Double
    var availableBalance: Double?
    var currencyCode: String
    var liability: FinanceLiability?

    var displayName: String { officialName?.isEmpty == false ? officialName! : name }
    var maskedName: String {
        guard let mask, !mask.isEmpty else { return displayName }
        return "\(displayName) ••\(mask)"
    }
}

enum FinanceTransactionDirection: String, Codable, Hashable {
    case inflow
    case outflow
}

struct FinanceTransaction: Identifiable, Codable, Hashable {
    var id: String
    var accountID: String
    var date: String
    var name: String
    var merchantName: String?
    var category: String?
    /// Always positive. `direction` carries the meaning so Plaid's raw amount
    /// convention never leaks into the UI.
    var amount: Double
    var direction: FinanceTransactionDirection
    var pending: Bool
    var currencyCode: String

    var displayName: String { merchantName?.isEmpty == false ? merchantName! : name }
}

struct FinanceInstitution: Identifiable, Codable, Hashable {
    /// The server-side Plaid Item identifier. It is non-secret and is used only
    /// to let the user disconnect the corresponding institution.
    var id: String
    var name: String
    var accountCount: Int
    var needsAttention: Bool
}

enum FinanceRecurringCadence: String, Codable, Hashable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case annual
    case irregular

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 months"
        case .annual: "Yearly"
        case .irregular: "Recurring"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .irregular
    }
}

/// A repeated posted outflow inferred from cadence and amount consistency.
/// It is an estimate—not a guarantee that the merchant will charge again.
struct FinanceRecurringPayment: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var category: String?
    var amount: Double
    var monthlyAmount: Double
    var currencyCode: String
    var cadence: FinanceRecurringCadence
    var lastChargeDate: String
    var nextExpectedDate: String?
    var occurrences: Int
    /// Optional so cached snapshots and older deployed backends continue to decode.
    var chargesLast12Months: Int?
    var spentLast12Months: Double?
    var isVariable: Bool
    var confidence: Double
}

struct FinanceSpendingCategory: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var amount: Double
    var share: Double
}

/// A compact read model produced by Orbit's backend. The backend owns Plaid
/// cursors, encrypted access tokens, and raw provider responses.
struct FinanceOverview: Codable, Hashable {
    var institutions: [FinanceInstitution]
    var accounts: [FinanceAccount]
    var recentTransactions: [FinanceTransaction]
    var monthlyInflow: Double
    var monthlyOutflow: Double
    var totalCash: Double
    var totalCreditBalance: Double
    var totalInvestments: Double
    /// Optional for rolling compatibility with older deployed backends.
    var recurringPayments: [FinanceRecurringPayment]?
    var monthlyRecurringTotal: Double?
    var spendingByCategory: [FinanceSpendingCategory]?
    var currencyCode: String
    var lastUpdatedAt: String?

    var monthlyNetFlow: Double { monthlyInflow - monthlyOutflow }
    var detectedRecurringPayments: [FinanceRecurringPayment] { recurringPayments ?? [] }
    var detectedMonthlyRecurringTotal: Double {
        monthlyRecurringTotal
            ?? detectedRecurringPayments.reduce(0) { $0 + $1.monthlyAmount }
    }
    var topSpendingCategories: [FinanceSpendingCategory] { spendingByCategory ?? [] }

    /// Prefer Plaid's stable Item identifier. The name match supports cached
    /// payloads from older backend versions that did not preserve the Item ID.
    func accounts(for institution: FinanceInstitution) -> [FinanceAccount] {
        let exactMatches = accounts.filter { $0.itemID == institution.id }
        if !exactMatches.isEmpty { return exactMatches }

        return accounts.filter {
            FinanceInstitutionName.matches($0.institutionName, institution.name)
        }
    }

    func transactions(for institution: FinanceInstitution) -> [FinanceTransaction] {
        let accountIDs = Set(accounts(for: institution).map(\.id))
        return recentTransactions.filter { accountIDs.contains($0.accountID) }
    }

    func institution(for account: FinanceAccount) -> FinanceInstitution? {
        if let exactMatch = institutions.first(where: { $0.id == account.itemID }) {
            return exactMatch
        }

        return institutions.first {
            FinanceInstitutionName.matches($0.name, account.institutionName)
        }
    }
}

/// A short-lived, server-created Plaid Hosted Link session. Orbit opens this
/// URL in Apple's secure authentication browser; no Plaid credential or access
/// token is ever returned to the app.
struct PlaidHostedLinkLaunch: Decodable, Hashable {
    var hostedLinkURL: URL
    var connectionID: String
    var expiresAt: String?
}

enum PlaidHostedLinkState: String, Decodable, Hashable {
    case pending
    case processing
    case complete
    case exited
    case failed
    case expired
}

struct PlaidHostedLinkStatus: Decodable, Hashable {
    var connectionID: String
    var status: PlaidHostedLinkState
    var expiresAt: String?
    var completedAt: String?
    var message: String?
}

struct PlaidHostedLinkStatusEnvelope: Decodable, Hashable {
    var data: PlaidHostedLinkStatus
}

struct FinanceOverviewEnvelope: Decodable {
    var data: FinanceOverview
}

struct FinanceDisconnectEnvelope: Decodable {
    var removed: Bool
}

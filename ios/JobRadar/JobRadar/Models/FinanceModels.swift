import Foundation

/// Typed destinations owned by Finance's navigation stack. Deep links, widgets,
/// and in-app links all route through this enum instead of scattering strings
/// through individual views.
enum FinanceRoute: String, Hashable, Codable {
    case income
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
    var currencyCode: String
    var lastUpdatedAt: String?

    var monthlyNetFlow: Double { monthlyInflow - monthlyOutflow }
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

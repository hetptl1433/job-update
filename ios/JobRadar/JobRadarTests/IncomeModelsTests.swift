import Foundation
import XCTest
#if canImport(HealthKit)
import HealthKit
#endif
@testable import JobRadar

final class IncomeCalculatorTests: XCTestCase {
    func testStandardHourlyExampleUsesCorrectFrequencyDivisors() {
        let source = IncomeCalculatorSource(
            name: "Hourly role",
            mode: .hourly,
            amount: 32,
            hoursPerWeek: 40,
            weeksPerYear: 52
        )

        let result = IncomeCalculator.calculate(sources: [source])

        XCTAssertEqual(result.basis, .gross)
        XCTAssertEqual(result.annual, 66_560)
        XCTAssertEqual(result.monthly, decimal("5546.67"))
        XCTAssertEqual(result.biweekly, 2_560)
        XCTAssertEqual(result.semimonthly, decimal("2773.33"))
        XCTAssertEqual(result.weekly, 1_280)
        XCTAssertEqual(result.daily, 256)
        XCTAssertEqual(result.hourly, 32)
    }

    func testMixedSourcesIncludeBonusAndAdditionalAnnualIncome() {
        let sources = [
            IncomeCalculatorSource(
                name: "IDOT",
                mode: .hourly,
                amount: 28,
                hoursPerWeek: 40,
                weeksPerYear: 52,
                annualBonus: 1_000,
                additionalAnnualIncome: 500
            ),
            IncomeCalculatorSource(
                name: "Consulting",
                mode: .hourly,
                amount: 35,
                hoursPerWeek: 8,
                weeksPerYear: 52
            ),
            IncomeCalculatorSource(
                name: "Other",
                mode: .monthly,
                amount: 500
            )
        ]

        let result = IncomeCalculator.calculate(sources: sources)

        XCTAssertEqual(result.annual, 80_300)
        XCTAssertEqual(result.monthly, decimal("6691.67"))
        XCTAssertEqual(result.biweekly, decimal("3088.46"))
    }

    func testDisabledSourcesDoNotAffectCalculation() {
        let active = IncomeCalculatorSource(
            name: "Active",
            mode: .annualSalary,
            amount: 72_000
        )
        let disabled = IncomeCalculatorSource(
            name: "Disabled",
            mode: .annualSalary,
            amount: 1_000_000,
            annualBonus: 100_000,
            isEnabled: false
        )

        XCTAssertEqual(
            IncomeCalculator.calculate(sources: [active, disabled]),
            IncomeGrossBreakdown(annual: 72_000)
        )
        XCTAssertEqual(IncomeCalculator.annualGross(for: disabled), 0)
    }

    func testAnnualSalaryProducesStandardEquivalents() {
        let source = IncomeCalculatorSource(
            name: "Salary",
            mode: .annualSalary,
            amount: 80_000
        )

        let result = IncomeCalculator.calculate(sources: [source])

        XCTAssertEqual(result.annual, 80_000)
        XCTAssertEqual(result.monthly, decimal("6666.67"))
        XCTAssertEqual(result.biweekly, decimal("3076.92"))
        XCTAssertEqual(result.semimonthly, decimal("3333.33"))
        XCTAssertEqual(result.weekly, decimal("1538.46"))
        XCTAssertEqual(result.daily, decimal("307.69"))
        XCTAssertEqual(result.hourly, decimal("38.46"))
    }

    func testOneTimeIncomeIsNotRepeatedAcrossTheYear() {
        let source = IncomeCalculatorSource(
            name: "One-time project",
            mode: .oneTime,
            amount: 2_500
        )

        let result = IncomeCalculator.calculate(sources: [source])

        XCTAssertEqual(result.annual, 2_500)
        XCTAssertEqual(result.monthly, decimal("208.33"))
        XCTAssertEqual(result.weekly, decimal("48.08"))
    }

    func testEmptyNegativeAndNonFiniteInputsBecomeZero() {
        XCTAssertEqual(IncomeCalculator.calculate(sources: []), .zero)

        let negative = IncomeCalculatorSource(
            name: "Invalid negative",
            mode: .hourly,
            amount: -32,
            hoursPerWeek: -40,
            weeksPerYear: -52,
            annualBonus: -1,
            additionalAnnualIncome: -1
        )
        let nonFinite = IncomeCalculatorSource(
            name: "Invalid non-finite",
            mode: .annualSalary,
            amount: .nan,
            annualBonus: .nan,
            additionalAnnualIncome: .nan
        )

        XCTAssertEqual(IncomeCalculator.calculate(sources: [negative, nonFinite]), .zero)
    }
}

final class IncomeTakeHomeCalculatorTests: XCTestCase {
    func testTakeHomeUsesOnlyEnteredRatesAndFixedDeductions() {
        let input = IncomeTakeHomeInput(
            grossAnnual: 100_000,
            state: "IN",
            federalTaxPercent: 20,
            stateTaxPercent: 5,
            ficaPercent: decimal("7.65"),
            retirement401kPercent: 6,
            annualHealthInsurance: 2_400,
            annualOtherDeductions: 600
        )

        let result = IncomeTakeHomeCalculator.estimate(input)

        XCTAssertTrue(result.isEstimate)
        XCTAssertEqual(result.basis, .estimatedNet)
        XCTAssertEqual(result.grossAnnual, 100_000)
        XCTAssertEqual(result.estimatedTaxesAnnual, 32_650)
        XCTAssertEqual(result.estimatedDeductionsAnnual, 9_000)
        XCTAssertEqual(result.estimatedTakeHomeAnnual, 58_350)
        XCTAssertEqual(result.takeHomeByFrequency.monthly, decimal("4862.50"))
        XCTAssertEqual(result.takeHomeByFrequency.basis, .estimatedNet)
    }

    func testStateNameDoesNotInferOrChangeATaxRate() {
        let indiana = IncomeTakeHomeInput(grossAnnual: 60_000, state: "IN", federalTaxPercent: 10)
        let california = IncomeTakeHomeInput(grossAnnual: 60_000, state: "CA", federalTaxPercent: 10)

        XCTAssertEqual(
            IncomeTakeHomeCalculator.estimate(indiana),
            IncomeTakeHomeCalculator.estimate(california)
        )
    }

    func testPercentagesAreBoundedAndTakeHomeNeverDropsBelowZero() {
        let overTaxed = IncomeTakeHomeInput(
            grossAnnual: 50_000,
            federalTaxPercent: 150,
            stateTaxPercent: 100,
            ficaPercent: 100,
            retirement401kPercent: 100,
            annualHealthInsurance: 50_000,
            annualOtherDeductions: 50_000
        )

        let result = IncomeTakeHomeCalculator.estimate(overTaxed)

        XCTAssertEqual(result.estimatedTaxesAnnual, 50_000)
        XCTAssertEqual(result.estimatedDeductionsAnnual, 0)
        XCTAssertEqual(result.estimatedTakeHomeAnnual, 0)
    }

    func testFixedDeductionsAreCappedAtAvailableGross() {
        let input = IncomeTakeHomeInput(
            grossAnnual: 10_000,
            federalTaxPercent: -10,
            stateTaxPercent: .nan,
            ficaPercent: -1,
            retirement401kPercent: -20,
            annualHealthInsurance: 7_000,
            annualOtherDeductions: 8_000
        )

        let result = IncomeTakeHomeCalculator.estimate(input)

        XCTAssertEqual(result.estimatedTaxesAnnual, 0)
        XCTAssertEqual(result.estimatedDeductionsAnnual, 10_000)
        XCTAssertEqual(result.estimatedTakeHomeAnnual, 0)
    }

    func testNegativeAndNonFiniteGrossBecomeZero() {
        XCTAssertEqual(
            IncomeTakeHomeCalculator.estimate(IncomeTakeHomeInput(grossAnnual: -1)).estimatedTakeHomeAnnual,
            0
        )
        XCTAssertEqual(
            IncomeTakeHomeCalculator.estimate(IncomeTakeHomeInput(grossAnnual: .nan)).estimatedTakeHomeAnnual,
            0
        )
    }
}

final class IncomeWireModelTests: XCTestCase {
    func testUnknownEnumValuesFallBackWithoutCountingAmbiguousIncome() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(IncomeType.self, from: jsonString("pension")), .other)
        XCTAssertEqual(try decoder.decode(PayFrequency.self, from: jsonString("fortnightly")), .irregular)
        XCTAssertEqual(
            try decoder.decode(IncomeClassification.self, from: jsonString("probably_income")),
            .needsReview
        )
        XCTAssertEqual(
            try decoder.decode(IncomeTransactionDirection.self, from: jsonString("sideways")),
            .unknown
        )
        XCTAssertEqual(
            try decoder.decode(IncomeCalculationMode.self, from: jsonString("mystery")),
            .oneTime
        )
        XCTAssertEqual(
            try decoder.decode(IncomeAmountBasis.self, from: jsonString("unclear")),
            .observedNetDeposit
        )
    }

    func testOverviewDecodesBackendJSONContractWithDecimalMoney() throws {
        let json = #"""
        {
          "summaries": [
            {
              "currencyCode": "USD",
              "basis": "observedNetDeposit",
              "thisMonth": {"confirmed": 5420.25, "pending": 1200, "needsReview": 350},
              "lastMonth": {"confirmed": 5110.25, "pending": 0, "needsReview": 75},
              "changeAmount": 310,
              "changePercent": 6.1,
              "yearToDate": 39840.50,
              "averageMonthly": 4980.06,
              "estimatedAnnual": 59760.72,
              "sources": [
                {
                  "id": "source-1",
                  "name": "Dometic Payroll",
                  "type": "salary",
                  "accountID": "account-1",
                  "frequency": "biweekly",
                  "averagePayment": 1840.25,
                  "averageMonthly": 3987.21,
                  "lastPaymentDate": "2026-08-02",
                  "nextExpectedPaymentDate": "2026-08-16",
                  "active": true,
                  "confidence": 0.98,
                  "userConfirmed": true,
                  "thisMonth": 3680.50,
                  "yearToDate": 29444,
                  "transactionCount": 16,
                  "basis": "observedNetDeposit"
                }
              ],
              "history": [
                {"month": "2026-07", "confirmed": 5110.25, "pending": 0, "needsReview": 75}
              ],
              "confirmedTransactions": [
                {
                  "id": "transaction-1",
                  "accountID": "account-1",
                  "date": "2026-08-02",
                  "authorizedDate": "2026-08-01",
                  "name": "DIRECT DEP DOMETIC",
                  "merchantName": "Dometic",
                  "category": "Payroll",
                  "amount": 1840.25,
                  "direction": "inflow",
                  "pending": false,
                  "currencyCode": "USD",
                  "sourceName": "Dometic Payroll",
                  "sourceType": "salary",
                  "confidence": 0.98,
                  "classificationReason": "Recurring employer deposit",
                  "userConfirmed": true,
                  "classification": "income",
                  "basis": "observedNetDeposit"
                }
              ],
              "needsReviewTransactions": [
                {
                  "id": "transaction-2",
                  "accountID": "account-1",
                  "date": "2026-08-08",
                  "name": "VENMO CASHOUT",
                  "amount": 350,
                  "direction": "inflow",
                  "pending": false,
                  "currencyCode": "USD",
                  "confidence": 0.42,
                  "classificationReason": "Ambiguous peer payment",
                  "userConfirmed": false,
                  "classification": "needsReview"
                }
              ],
              "projectedMonthEnd": 6620.25,
              "projectedYearEnd": 63240.50,
              "expectedPaychecks": [
                {
                  "sourceID": "source-1",
                  "sourceName": "Dometic Payroll",
                  "date": "2026-08-16",
                  "estimatedAmount": 1840.25,
                  "confidence": 0.91
                }
              ],
              "coverage": {
                "startDate": "2026-01-01",
                "endDate": "2026-08-09",
                "completeMonths": 7
              }
            }
          ],
          "lastUpdatedAt": "2026-08-09T15:00:00Z"
        }
        """#

        let overview = try JSONDecoder().decode(IncomeOverview.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(overview.summaries.first)

        XCTAssertEqual(overview.lastUpdatedAt, "2026-08-09T15:00:00Z")
        XCTAssertEqual(summary.currencyCode, "USD")
        XCTAssertEqual(summary.thisMonth.confirmed, decimal("5420.25"))
        XCTAssertEqual(summary.changeAmount, 310)
        XCTAssertEqual(summary.changePercent, decimal("6.1"))
        XCTAssertEqual(summary.amountBasis, .observedNetDeposit)
        XCTAssertEqual(summary.sources.first?.amountBasis, .observedNetDeposit)
        XCTAssertEqual(summary.sources.first?.frequency, .biweekly)
        XCTAssertEqual(summary.sources.first?.averagePayment, decimal("1840.25"))
        XCTAssertEqual(summary.confirmedTransactions.first?.amountBasis, .observedNetDeposit)
        XCTAssertEqual(summary.confirmedTransactions.first?.classification, .income)
        XCTAssertEqual(summary.needsReviewTransactions.first?.classification, .needsReview)
        XCTAssertEqual(summary.expectedPaychecks.first?.estimatedAmount, decimal("1840.25"))
        XCTAssertEqual(summary.coverage?.completeMonths, 7)
        XCTAssertEqual(summary.confirmedLast12Months, decimal("5110.25"))
    }

    func testNullableChangeAndOptionalProjectionFieldsDecodeWhenAbsent() throws {
        let json = #"""
        {
          "summaries": [
            {
              "currencyCode": "USD",
              "thisMonth": {"confirmed": 0, "pending": 0, "needsReview": 0},
              "lastMonth": {"confirmed": 0, "pending": 0, "needsReview": 0},
              "changeAmount": null,
              "changePercent": null,
              "yearToDate": 0,
              "averageMonthly": 0,
              "estimatedAnnual": null,
              "sources": [],
              "history": [],
              "confirmedTransactions": [],
              "needsReviewTransactions": [],
              "projectedMonthEnd": null,
              "projectedYearEnd": null,
              "expectedPaychecks": []
            }
          ],
          "lastUpdatedAt": null
        }
        """#

        let overview = try JSONDecoder().decode(IncomeOverview.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(overview.summaries.first)

        XCTAssertNil(summary.changeAmount)
        XCTAssertNil(summary.changePercent)
        XCTAssertNil(summary.estimatedAnnual)
        XCTAssertNil(summary.projectedMonthEnd)
        XCTAssertNil(summary.projectedYearEnd)
        XCTAssertNil(summary.coverage)
    }

    func testAccountOnlyCoverageCanHaveNoStartDate() throws {
        let json = #"{"startDate":null,"endDate":"2026-08-09","completeMonths":0}"#
        let coverage = try JSONDecoder().decode(IncomeDataCoverage.self, from: Data(json.utf8))

        XCTAssertNil(coverage.startDate)
        XCTAssertEqual(coverage.endDate, "2026-08-09")
        XCTAssertEqual(coverage.completeMonths, 0)
    }

    func testClassificationRequestUsesBackendCamelCaseValues() throws {
        let request = IncomeClassificationRequest(
            classification: .notIncome,
            sourceName: "Internal transfer",
            type: .other,
            asOfDate: "2026-08-09",
            timeZone: "America/Indiana/Indianapolis"
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["classification"], "notIncome")
        XCTAssertEqual(object["sourceName"], "Internal transfer")
        XCTAssertEqual(object["type"], "other")
        XCTAssertEqual(object["asOfDate"], "2026-08-09")
        XCTAssertEqual(object["timeZone"], "America/Indiana/Indianapolis")
    }
}

final class FinanceOverviewWireModelTests: XCTestCase {
    func testOlderBackendOverviewStillDecodesWithoutInsightFields() throws {
        let json = #"""
        {
          "institutions": [],
          "accounts": [],
          "recentTransactions": [],
          "monthlyInflow": 2000,
          "monthlyOutflow": 900,
          "totalCash": 5000,
          "totalCreditBalance": 250,
          "totalInvestments": 1000,
          "currencyCode": "USD",
          "lastUpdatedAt": "2026-08-11T12:00:00Z"
        }
        """#

        let overview = try JSONDecoder().decode(FinanceOverview.self, from: Data(json.utf8))

        XCTAssertEqual(overview.detectedRecurringPayments, [])
        XCTAssertEqual(overview.detectedMonthlyRecurringTotal, 0)
        XCTAssertEqual(overview.topSpendingCategories, [])
    }

    func testRecurringAndSpendingInsightsDecodeFromBackendContract() throws {
        let json = #"""
        {
          "institutions": [],
          "accounts": [],
          "recentTransactions": [],
          "monthlyInflow": 2000,
          "monthlyOutflow": 900,
          "totalCash": 5000,
          "totalCreditBalance": 250,
          "totalInvestments": 1000,
          "recurringPayments": [{
            "id": "subscription-1",
            "name": "Streamflix",
            "category": "Entertainment",
            "amount": 15.99,
            "monthlyAmount": 15.99,
            "currencyCode": "USD",
            "cadence": "monthly",
            "lastChargeDate": "2026-08-05",
            "nextExpectedDate": "2026-09-05",
            "occurrences": 5,
            "chargesLast12Months": 5,
            "spentLast12Months": 79.95,
            "isVariable": false,
            "confidence": 0.96
          }],
          "monthlyRecurringTotal": 15.99,
          "spendingByCategory": [{
            "id": "rent-and-utilities",
            "name": "Rent And Utilities",
            "amount": 700,
            "share": 0.7778
          }],
          "currencyCode": "USD",
          "lastUpdatedAt": "2026-08-11T12:00:00Z"
        }
        """#

        let overview = try JSONDecoder().decode(FinanceOverview.self, from: Data(json.utf8))

        XCTAssertEqual(overview.detectedRecurringPayments.first?.cadence, .monthly)
        XCTAssertEqual(overview.detectedRecurringPayments.first?.nextExpectedDate, "2026-09-05")
        XCTAssertEqual(overview.detectedRecurringPayments.first?.chargesLast12Months, 5)
        XCTAssertEqual(overview.detectedRecurringPayments.first?.spentLast12Months, 79.95)
        XCTAssertEqual(overview.detectedMonthlyRecurringTotal, 15.99)
        XCTAssertEqual(overview.topSpendingCategories.first?.amount, 700)
    }

    func testUnknownRecurringCadenceFallsBackWithoutBreakingFinance() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(FinanceRecurringCadence.self, from: jsonString("semimonthly")),
            .irregular
        )
    }
}

final class FinanceSpendingAnalysisTests: XCTestCase {
    func testDashboardGroupsOnlyPostedOutflowsInTheOverviewCurrency() {
        let referenceDate = utcDate(year: 2026, month: 8, day: 27)
        let overview = makeOverview(transactions: [
            transaction(id: "food-1", date: "2026-08-10", category: "Food And Drink", amount: 80),
            transaction(id: "food-2", date: "2026-08-15", category: "Food And Drink", amount: 20),
            transaction(id: "travel", date: "2026-08-20", category: "Travel", amount: 50),
            transaction(id: "pending", date: "2026-08-21", category: "Travel", amount: 999, pending: true),
            transaction(id: "deposit", date: "2026-08-22", category: "Income", amount: 2_000, direction: .inflow),
            transaction(id: "eur", date: "2026-08-23", category: "Travel", amount: 500, currencyCode: "EUR"),
            transaction(id: "old", date: "2026-07-31", category: "Other", amount: 100)
        ])

        let result = FinanceSpendingAnalysis.make(
            overview: overview,
            period: .thisMonth,
            relativeTo: referenceDate,
            calendar: utcCalendar
        )

        XCTAssertEqual(result.totalSpent, 150, accuracy: 0.001)
        XCTAssertEqual(result.transactionCount, 3)
        XCTAssertEqual(result.categories.map(\.name), ["Food And Drink", "Travel"])
        XCTAssertEqual(result.categories[0].amount, 100, accuracy: 0.001)
        XCTAssertEqual(result.categories[0].share, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(result.categories[0].transactionCount, 2)
        XCTAssertEqual(result.averageTransaction, 50, accuracy: 0.001)
        XCTAssertEqual(result.largestTransaction?.id, "food-1")
    }

    func testCurrentMonthCanUseBackendBreakdownBeforeTransactionsArrive() {
        var overview = makeOverview(transactions: [])
        overview.monthlyOutflow = 400
        overview.spendingByCategory = [
            FinanceSpendingCategory(
                id: "rent-and-utilities",
                name: "Rent And Utilities",
                amount: 300,
                share: 0.75
            ),
            FinanceSpendingCategory(
                id: "food-and-drink",
                name: "Food And Drink",
                amount: 100,
                share: 0.25
            )
        ]

        let result = FinanceSpendingAnalysis.make(
            overview: overview,
            period: .thisMonth,
            relativeTo: utcDate(year: 2026, month: 8, day: 27),
            calendar: utcCalendar
        )

        XCTAssertEqual(result.totalSpent, 400, accuracy: 0.001)
        XCTAssertEqual(result.transactionCount, 0)
        XCTAssertEqual(result.topCategory?.name, "Rent And Utilities")
        XCTAssertEqual(result.topCategory?.share ?? 0, 0.75, accuracy: 0.001)
    }

    func testCardPaymentStaysInActivityButDoesNotDoubleCountTheCardPurchase() {
        let referenceDate = utcDate(year: 2026, month: 8, day: 27)
        let purchase = transaction(
            id: "amazon",
            date: "2026-08-10",
            category: "General Merchandise",
            amount: 120,
            name: "Amazon"
        )
        let payment = transaction(
            id: "amex-payment",
            date: "2026-08-20",
            category: "Loan Payments",
            amount: 120,
            name: "AMEX EPAYMENT"
        )
        let overview = makeOverview(transactions: [purchase, payment])

        let result = FinanceSpendingAnalysis.make(
            overview: overview,
            period: .thisMonth,
            relativeTo: referenceDate,
            calendar: utcCalendar
        )

        XCTAssertEqual(overview.recentTransactions.count, 2)
        XCTAssertEqual(payment.resolvedNature, .creditCardPayment)
        XCTAssertEqual(payment.displayCategory, "Credit Card Payment")
        XCTAssertFalse(payment.countsAsSpending)
        XCTAssertEqual(result.totalSpent, 120, accuracy: 0.001)
        XCTAssertEqual(result.transactions.map(\.id), [purchase.id])
        XCTAssertEqual(result.categories.map(\.name), ["Shopping"])
    }

    func testLegacyBackendBreakdownCanonicalizesShoppingAndDropsCardSettlement() {
        var overview = makeOverview(transactions: [])
        overview.monthlyOutflow = 320
        overview.spendingByCategory = [
            FinanceSpendingCategory(
                id: "general-merchandise",
                name: "General Merchandise",
                amount: 120,
                share: 0.375
            ),
            FinanceSpendingCategory(
                id: "loan-payments",
                name: "Loan Payments",
                amount: 200,
                share: 0.625
            )
        ]

        let result = FinanceSpendingAnalysis.make(
            overview: overview,
            period: .thisMonth,
            relativeTo: utcDate(year: 2026, month: 8, day: 27),
            calendar: utcCalendar
        )

        XCTAssertEqual(result.totalSpent, 120, accuracy: 0.001)
        XCTAssertEqual(result.categories.map(\.name), ["Shopping"])
        XCTAssertEqual(result.categories.first?.share ?? 0, 1, accuracy: 0.001)
    }

    func testLegacyRecurringCardBillIsNotTreatedAsAnotherSubscription() {
        var overview = makeOverview(transactions: [])
        overview.recurringPayments = [
            FinanceRecurringPayment(
                id: "amex-payment",
                name: "AMEX EPAYMENT",
                category: "Loan Payments",
                amount: 500,
                monthlyAmount: 500,
                currencyCode: "USD",
                cadence: .monthly,
                lastChargeDate: "2026-08-20",
                nextExpectedDate: "2026-09-20",
                occurrences: 4,
                chargesLast12Months: 4,
                spentLast12Months: 2_000,
                isVariable: true,
                confidence: 0.9
            )
        ]
        overview.monthlyRecurringTotal = 500

        XCTAssertTrue(overview.detectedRecurringPayments.isEmpty)
        XCTAssertEqual(overview.detectedMonthlyRecurringTotal, 0, accuracy: 0.001)
    }

    func testVagueRestaurantChargeStaysInFoodAndDrink() {
        let value = transaction(
            id: "dinner",
            date: "2026-08-20",
            category: "Other",
            amount: 42,
            name: "DOORDASH *LOCAL RESTAURANT"
        )

        XCTAssertEqual(value.displayCategory, "Food And Drink")
    }

    func testAIMerchantCategoryIsRememberedAndReapplied() {
        let value = transaction(
            id: "mystery",
            date: "2026-08-20",
            category: "Other",
            amount: 28,
            name: "MYSTERY BOOK CLUB"
        )
        let key = FinanceCategoryName.merchantKey(for: value)
        var memory = FinanceCategoryMemory()
        memory.remember([
            FinanceMerchantCategoryRule(
                merchantKey: key,
                category: .education,
                confidence: 0.88,
                reason: "The merchant appears to be a book service.",
                source: .ai,
                learnedAt: .now
            )
        ])

        let categorized = memory.applying(to: makeOverview(transactions: [value]))

        XCTAssertEqual(categorized.recentTransactions.first?.category, "Education")
        XCTAssertEqual(categorized.recentTransactions.first?.categorySource, .ai)
        XCTAssertTrue(memory.unclassifiedSamples(in: categorized).isEmpty)
    }

    func testAILearnedSubscriptionBecomesAReviewSuggestion() {
        let value = transaction(
            id: "digital-plan",
            date: "2026-08-22",
            category: "Other",
            amount: 12,
            name: "MYSTERY DIGITAL SERVICE"
        )
        let key = FinanceCategoryName.merchantKey(for: value)
        var memory = FinanceCategoryMemory()
        memory.remember([
            FinanceMerchantCategoryRule(
                merchantKey: key,
                category: .subscriptions,
                confidence: 0.84,
                reason: "The descriptor identifies a digital service plan.",
                source: .ai,
                learnedAt: .now
            )
        ])

        let categorized = memory.applying(to: makeOverview(transactions: [value]))

        XCTAssertEqual(categorized.possibleSubscriptions.count, 1)
        XCTAssertEqual(categorized.possibleSubscriptions.first?.category, "Subscriptions")
        XCTAssertEqual(categorized.detectedMonthlyRecurringTotal, 0, accuracy: 0.001)
    }

    func testNewOpenAIAndPlayStationChargesAppearAsUncountedSuggestions() {
        let overview = makeOverview(transactions: [
            transaction(
                id: "openai",
                date: "2026-08-20",
                category: "Other",
                amount: 20,
                name: "OPENAI *CHATGPT SUBSCRIPTION"
            ),
            transaction(
                id: "playstation",
                date: "2026-08-21",
                category: "Entertainment",
                amount: 17.99,
                name: "PLAYSTATION NETWORK"
            )
        ])

        XCTAssertEqual(Set(overview.possibleSubscriptions.map(\.name)), ["OpenAI", "PlayStation"])
        XCTAssertTrue(overview.confirmedRecurringPayments.isEmpty)
        XCTAssertEqual(overview.detectedMonthlyRecurringTotal, 0, accuracy: 0.001)
    }

    func testKnownSubscriptionConfirmsAfterTwoMonthlyCharges() {
        let overview = makeOverview(transactions: [
            transaction(
                id: "openai-july",
                date: "2026-07-20",
                category: "Other",
                amount: 20,
                name: "OPENAI CHATGPT PLUS"
            ),
            transaction(
                id: "openai-august",
                date: "2026-08-20",
                category: "Other",
                amount: 20,
                name: "OPENAI *CHATGPT SUBSCRIPTION 8392"
            )
        ])

        XCTAssertEqual(overview.confirmedRecurringPayments.count, 1)
        XCTAssertEqual(overview.confirmedRecurringPayments.first?.name, "OpenAI")
        XCTAssertEqual(overview.confirmedRecurringPayments.first?.cadence, .monthly)
        XCTAssertEqual(overview.detectedMonthlyRecurringTotal, 20, accuracy: 0.001)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func transaction(
        id: String,
        date: String,
        category: String,
        amount: Double,
        direction: FinanceTransactionDirection = .outflow,
        pending: Bool = false,
        currencyCode: String = "USD",
        name: String? = nil,
        merchantName: String? = nil,
        nature: FinanceTransactionNature? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountID: "checking",
            date: date,
            name: name ?? id,
            merchantName: merchantName,
            category: category,
            amount: amount,
            direction: direction,
            nature: nature,
            pending: pending,
            currencyCode: currencyCode
        )
    }

    private func makeOverview(transactions: [FinanceTransaction]) -> FinanceOverview {
        FinanceOverview(
            institutions: [],
            accounts: [],
            recentTransactions: transactions,
            monthlyInflow: 0,
            monthlyOutflow: 0,
            totalCash: 0,
            totalCreditBalance: 0,
            totalInvestments: 0,
            recurringPayments: nil,
            monthlyRecurringTotal: nil,
            spendingByCategory: nil,
            currencyCode: "USD",
            lastUpdatedAt: nil
        )
    }
}

final class FinanceInstitutionPresentationTests: XCTestCase {
    func testCommonInstitutionNameVariantsResolveToNativeBrandMarks() {
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "JPMorgan Chase Bank"), .chase)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "AMEX Personal Savings"), .americanExpress)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "Discover Card"), .discover)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "Bank of America"), .bankOfAmerica)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "Capital One 360"), .capitalOne)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "Fifth Third Bank"), .fifthThird)
        XCTAssertEqual(FinanceInstitutionBrand(institutionName: "A Local Credit Union"), .generic)
    }

    func testRequestedInstitutionsResolveToOwnerSuppliedAssetCatalogMarks() {
        XCTAssertEqual(FinanceInstitutionBrand.chase.officialLogoAssetName, "FinanceLogoChase")
        XCTAssertEqual(
            FinanceInstitutionBrand.americanExpress.officialLogoAssetName,
            "FinanceLogoAmericanExpress"
        )
        XCTAssertEqual(FinanceInstitutionBrand.discover.officialLogoAssetName, "FinanceLogoDiscover")
        XCTAssertNil(FinanceInstitutionBrand.generic.officialLogoAssetName)
    }

    func testAccountKindsStayInSeparateBankCardAndOtherGroups() {
        XCTAssertEqual(account(id: "checking", itemID: "item", kind: .checking).group, .bank)
        XCTAssertEqual(account(id: "savings", itemID: "item", kind: .savings).group, .bank)
        XCTAssertEqual(account(id: "card", itemID: "item", kind: .creditCard).group, .creditCards)
        XCTAssertEqual(account(id: "investment", itemID: "item", kind: .investment).group, .other)
        XCTAssertEqual(account(id: "loan", itemID: "item", kind: .loan).group, .other)
    }

    func testInstitutionDetailUsesItemIDAndOnlyItsAccountTransactions() {
        let chase = FinanceInstitution(id: "item-chase", name: "Chase", accountCount: 2, needsAttention: false)
        let amex = FinanceInstitution(id: "item-amex", name: "American Express", accountCount: 1, needsAttention: false)
        let chaseChecking = account(id: "chase-checking", itemID: chase.id, institution: "Chase", kind: .checking)
        let chaseCard = account(id: "chase-card", itemID: chase.id, institution: "Chase", kind: .creditCard)
        let amexCard = account(id: "amex-card", itemID: amex.id, institution: "American Express", kind: .creditCard)
        let overview = overview(
            institutions: [chase, amex],
            accounts: [chaseChecking, chaseCard, amexCard],
            transactions: [
                transaction(id: "chase-transaction", accountID: chaseChecking.id),
                transaction(id: "amex-transaction", accountID: amexCard.id)
            ]
        )

        XCTAssertEqual(Set(overview.accounts(for: chase).map(\.id)), ["chase-checking", "chase-card"])
        XCTAssertEqual(overview.transactions(for: chase).map(\.id), ["chase-transaction"])
        XCTAssertEqual(overview.institution(for: amexCard), amex)
    }

    func testLegacyCachedAccountCanFallBackToInstitutionBrandName() {
        let amex = FinanceInstitution(
            id: "new-item-id",
            name: "American Express",
            accountCount: 1,
            needsAttention: false
        )
        let cachedAccount = account(
            id: "legacy-account",
            itemID: "legacy-item-id",
            institution: "AMEX Personal Savings",
            kind: .savings
        )
        let overview = overview(institutions: [amex], accounts: [cachedAccount], transactions: [])

        XCTAssertEqual(overview.accounts(for: amex).map(\.id), [cachedAccount.id])
        XCTAssertEqual(overview.institution(for: cachedAccount), amex)
    }

    private func account(
        id: String,
        itemID: String,
        institution: String = "Test Bank",
        kind: FinanceAccountKind
    ) -> FinanceAccount {
        FinanceAccount(
            id: id,
            itemID: itemID,
            institutionName: institution,
            name: kind.label,
            officialName: nil,
            mask: "1234",
            kind: kind,
            subtype: nil,
            currentBalance: 100,
            availableBalance: 90,
            currencyCode: "USD",
            liability: nil
        )
    }

    private func transaction(id: String, accountID: String) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountID: accountID,
            date: "2026-08-11",
            name: "Transaction",
            merchantName: nil,
            category: "Test",
            amount: 10,
            direction: .outflow,
            pending: false,
            currencyCode: "USD"
        )
    }

    private func overview(
        institutions: [FinanceInstitution],
        accounts: [FinanceAccount],
        transactions: [FinanceTransaction]
    ) -> FinanceOverview {
        FinanceOverview(
            institutions: institutions,
            accounts: accounts,
            recentTransactions: transactions,
            monthlyInflow: 0,
            monthlyOutflow: 0,
            totalCash: 0,
            totalCreditBalance: 0,
            totalInvestments: 0,
            recurringPayments: nil,
            monthlyRecurringTotal: nil,
            spendingByCategory: nil,
            currencyCode: "USD",
            lastUpdatedAt: nil
        )
    }
}

final class ProtectedSnapshotStoreTests: XCTestCase {
    private struct Fixture: Codable, Equatable {
        var value: String
    }

    func testSnapshotIsOwnerScopedAndRemovable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProtectedSnapshotStore<Fixture>(filename: "fixture.json", directory: directory)

        store.save(Fixture(value: "cached"), ownerID: "owner-a")

        XCTAssertEqual(store.load(ownerID: "owner-a")?.value, Fixture(value: "cached"))
        XCTAssertNil(store.load(ownerID: "owner-b"))
        XCTAssertTrue(store.remove())
        XCTAssertNil(store.load(ownerID: "owner-a"))
    }

    func testSnapshotReportsAWriteFailure() throws {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-snapshot-blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let store = ProtectedSnapshotStore<Fixture>(
            filename: "fixture.json",
            directory: blockingFile.appendingPathComponent("child", isDirectory: true)
        )

        XCTAssertFalse(store.save(Fixture(value: "cached"), ownerID: "owner-a"))
        XCTAssertNil(store.load(ownerID: "owner-a"))
    }

    func testInboxMessageCanRoundTripThroughProtectedCachePayload() throws {
        let message = InboxMessage(
            id: "message-1",
            provider: .gmail,
            accountID: "gmail-1",
            accountEmail: "person@example.com",
            senderName: "Recruiter",
            senderEmail: "recruiter@example.com",
            subject: "Interview",
            aiSummary: "Choose an interview time.",
            receivedAt: Date(timeIntervalSince1970: 1_786_435_200),
            importance: .high,
            actionRequired: true,
            section: .needsAction
        )

        let decoded = try JSONDecoder().decode(
            InboxMessage.self,
            from: JSONEncoder().encode(message)
        )

        XCTAssertEqual(decoded, message)
    }
}

final class UnifiedToDoMigrationTests: XCTestCase {
    func testLegacyReminderBecomesScheduledToDoWithoutLosingLinks() {
        let id = UUID()
        let fireDate = Date(timeIntervalSince1970: 1_786_438_800)
        let reminder = ReminderItem(
            id: id,
            title: "Call recruiter",
            notes: "Ask about next steps",
            fireDate: fireDate,
            isCompleted: false,
            createdAt: fireDate.addingTimeInterval(-3_600),
            updatedAt: fireDate,
            relatedCalendarEventID: "apple:event-1",
            alertStyle: .notification
        )

        let result = SharedTaskStore.merging([], with: [reminder])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, id)
        XCTAssertEqual(result[0].title, "Call recruiter")
        XCTAssertEqual(result[0].notes, "Ask about next steps")
        XCTAssertEqual(result[0].dueDate, fireDate)
        XCTAssertEqual(result[0].appleCalendarEventID, "apple:event-1")
        XCTAssertEqual(result[0].effectiveAlertStyle, .notification)
    }

    func testExistingToDoWinsMigrationIDCollision() {
        let id = UUID()
        let task = TaskItem(id: id, title: "Current To Do")
        let reminder = ReminderItem(id: id, title: "Legacy Reminder")

        let result = SharedTaskStore.merging([task], with: [reminder])

        XCTAssertEqual(result, [task])
    }
}

final class AssistantConversationModelTests: XCTestCase {
    func testChatMessageHistoryRoundTripsForPersistentConversation() throws {
        let messages = [
            ChatMessage(role: .user, text: "What should I do today?"),
            ChatMessage(role: .assistant, text: "Start with your interview follow-up.")
        ]

        let data = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: data)

        XCTAssertEqual(decoded, messages)
    }
}

@MainActor
final class AssistantMemoryTests: XCTestCase {
    func testExplicitCommandsDoNotTreatOrdinaryConversationAsAMemoryWrite() {
        XCTAssertEqual(
            AssistantMemoryCommand.parse("Please remember that I prefer short answers"),
            .remember("I prefer short answers")
        )
        XCTAssertEqual(
            AssistantMemoryCommand.parse("forget that I prefer short answers"),
            .forget("I prefer short answers")
        )
        XCTAssertEqual(AssistantMemoryCommand.parse("clear my memories"), .forgetAll)
        XCTAssertNil(AssistantMemoryCommand.parse("I prefer short answers"))
    }

    func testMemoryIsDurableOwnerScopedAndCanBeDisabled() throws {
        let directory = temporaryTestDirectory("assistant-memory")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = AssistantMemoryRepository(directory: directory)
        first.load(ownerID: "owner-a")
        guard case .saved(let saved) = first.remember("I prefer short, direct answers") else {
            return XCTFail("Expected an approved memory to be saved")
        }
        XCTAssertEqual(saved.category, .communication)

        let restored = AssistantMemoryRepository(directory: directory)
        restored.load(ownerID: "owner-a")
        XCTAssertEqual(restored.memories.map(\.text), ["I prefer short, direct answers"])
        XCTAssertEqual(
            restored.relevant(for: "How should you answer me?").map(\.text),
            ["I prefer short, direct answers"]
        )

        restored.setEnabled(false)
        XCTAssertTrue(restored.relevant(for: "How should you answer me?").isEmpty)

        let otherOwner = AssistantMemoryRepository(directory: directory)
        otherOwner.load(ownerID: "owner-b")
        XCTAssertTrue(otherOwner.memories.isEmpty)
        guard case .saved = otherOwner.remember("My goal is to learn Swift") else {
            return XCTFail("The second owner should have independent memory")
        }

        let firstOwnerAgain = AssistantMemoryRepository(directory: directory)
        firstOwnerAgain.load(ownerID: "owner-a")
        XCTAssertEqual(firstOwnerAgain.memories.map(\.text), ["I prefer short, direct answers"])
    }

    func testMemoryRejectsSecretsAndLongFinancialIdentifiers() {
        let directory = temporaryTestDirectory("assistant-sensitive")
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = AssistantMemoryRepository(directory: directory)
        memory.load(ownerID: "owner")

        guard case .rejected = memory.remember("My password is violet") else {
            return XCTFail("Passwords must not enter Personal Memory")
        }
        guard case .rejected = memory.remember("My account number is 123456789") else {
            return XCTFail("Long financial identifiers must not enter Personal Memory")
        }
        XCTAssertTrue(memory.memories.isEmpty)
    }

    func testMemoryDoesNotClaimSavedWhenProtectedWriteFails() throws {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-memory-blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let impossibleDirectory = blockingFile.appendingPathComponent("child", isDirectory: true)
        let memory = AssistantMemoryRepository(directory: impossibleDirectory)
        memory.load(ownerID: "owner")

        guard case .failed = memory.remember("I prefer concise answers") else {
            return XCTFail("A failed disk write must not be reported as saved")
        }
        XCTAssertTrue(memory.memories.isEmpty)
    }

    func testPromptSeparatesApprovedMemoryFromInstructionsAndKeepsTransparencyRule() {
        let context = AssistantContext(
            userName: "Het",
            lines: ["Task: Call recruiter"],
            memoryLines: ["Preference: I prefer short answers"]
        )
        let input = AssistantPrompt.conversationInput(
            prompt: "What should I do?",
            history: [],
            context: context
        )

        XCTAssertTrue(input.contains("USER-APPROVED SAVED MEMORY"))
        XCTAssertTrue(input.contains("Preference: I prefer short answers"))
        XCTAssertTrue(input.contains("CURRENT ORBIT DATA"))
        XCTAssertTrue(AssistantPrompt.system.contains("Never pretend to be human"))
    }

    func testChatLearningSuggestionsStayPendingUntilApproved() {
        let directory = temporaryTestDirectory("assistant-suggestions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = AssistantMemoryRepository(directory: directory)
        memory.load(ownerID: "owner")
        XCTAssertTrue(memory.setSuggestionsEnabled(true))

        XCTAssertTrue(memory.suggestMemory(from: "I prefer concise answers"))
        XCTAssertTrue(memory.memories.isEmpty)
        let suggestion = try? XCTUnwrap(memory.pendingSuggestions.first)
        XCTAssertTrue(memory.relevant(for: "How should you answer?").isEmpty)
        XCTAssertTrue(memory.approvedForLiveSession().isEmpty)

        if let suggestion {
            guard case .saved = memory.acceptSuggestion(suggestion) else {
                return XCTFail("An approved suggestion should become memory")
            }
        }
        XCTAssertEqual(memory.memories.map(\.text), ["I prefer concise answers"])
        XCTAssertTrue(memory.pendingSuggestions.isEmpty)
        XCTAssertEqual(
            memory.approvedForLiveSession().map(\.text),
            ["I prefer concise answers"]
        )
    }

    func testUnrelatedMemoriesAreNotSentAsContext() {
        let directory = temporaryTestDirectory("assistant-relevance")
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = AssistantMemoryRepository(directory: directory)
        memory.load(ownerID: "owner")
        guard case .saved = memory.remember("I usually run before breakfast") else {
            return XCTFail("Expected routine to save")
        }

        XCTAssertTrue(memory.relevant(for: "Help me write a recruiter email").isEmpty)
        XCTAssertEqual(
            memory.relevant(for: "What is my breakfast routine?").map(\.text),
            ["I usually run before breakfast"]
        )
    }

    func testForgetRequiresAWholeWordMatch() {
        let directory = temporaryTestDirectory("assistant-forget")
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = AssistantMemoryRepository(directory: directory)
        memory.load(ownerID: "owner")
        guard case .saved = memory.remember("AI") else {
            return XCTFail("Expected memory to save")
        }

        XCTAssertFalse(memory.forget(matching: "chair"))
        XCTAssertEqual(memory.memories.map(\.text), ["AI"])
        XCTAssertTrue(memory.forget(matching: "AI"))
        XCTAssertTrue(memory.memories.isEmpty)
    }
}

@MainActor
final class IncrementalEmailScanTests: XCTestCase {
    func testSuccessfulScanRestoresPendingUpdatesCursorAndProcessedIDs() throws {
        let directory = temporaryTestDirectory("email-scan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let completedAt = Date(timeIntervalSince1970: 1_786_435_200)
        let receivedAt = completedAt.addingTimeInterval(-120)
        let message = emailMessage(id: "gmail:account-a:message-1", receivedAt: receivedAt)
        let update = jobUpdate(sourceMessageID: message.id)

        let first = EmailScanHistoryStore(directory: directory)
        first.load(ownerID: "owner-a")
        first.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [message],
            jobUpdates: [update],
            cursorDate: completedAt
        )

        let restored = EmailScanHistoryStore(directory: directory)
        restored.load(ownerID: "owner-a")
        XCTAssertEqual(restored.processedMessageIDs(for: "gmail:account-a"), [message.id])
        XCTAssertEqual(
            restored.receivedAfter(for: "gmail:account-a"),
            completedAt.addingTimeInterval(-600)
        )
        XCTAssertEqual(restored.pendingJobUpdates, [update])

        restored.recordJobDecision(.dismissed, for: update)
        let afterDecision = EmailScanHistoryStore(directory: directory)
        afterDecision.load(ownerID: "owner-a")
        XCTAssertTrue(afterDecision.pendingJobUpdates.isEmpty)

        let otherOwner = EmailScanHistoryStore(directory: directory)
        otherOwner.load(ownerID: "owner-b")
        XCTAssertTrue(otherOwner.processedMessageIDs(for: "gmail:account-a").isEmpty)
        XCTAssertTrue(otherOwner.pendingJobUpdates.isEmpty)
    }

    func testStableJobDecisionKeyAndCrossAccountMessageIDsDoNotCollide() {
        let first = jobUpdate(sourceMessageID: "gmail:account-a:same-provider-id")
        let repeated = jobUpdate(sourceMessageID: "gmail:account-a:same-provider-id")
        let otherAccount = jobUpdate(sourceMessageID: "gmail:account-b:same-provider-id")

        XCTAssertEqual(first.decisionKey, repeated.decisionKey)
        XCTAssertNotEqual(first.decisionKey, otherAccount.decisionKey)
    }

    func testInboxMergeRetainsPriorResultsAndPrunesExpiredMessages() {
        let directory = temporaryTestDirectory("inbox-merge")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = EmailRepository(snapshotStore: ProtectedSnapshotStore(
            filename: "inbox.json",
            directory: directory
        ))
        let now = Date(timeIntervalSince1970: 1_786_435_200)
        let current = inboxMessage(id: "current", receivedAt: now.addingTimeInterval(-60))
        let expired = inboxMessage(id: "expired", receivedAt: now.addingTimeInterval(-61 * 24 * 60 * 60))

        repository.setMessages([current, expired])
        repository.finishRefreshWithoutChanges(now: now)
        XCTAssertEqual(Set(repository.allMessages.map(\.id)), ["current"])

        let newer = inboxMessage(id: "new", receivedAt: now)
        repository.mergeMessages([newer], now: now)
        XCTAssertEqual(Set(repository.allMessages.map(\.id)), ["current", "new"])
    }

    func testTaskDecisionSurvivesReload() {
        let directory = temporaryTestDirectory("email-task-decision")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = EmailScanHistoryStore(directory: directory)
        first.load(ownerID: "owner")
        first.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [emailMessage(id: "gmail:account-a:message-1")],
            jobUpdates: []
        )
        first.recordTaskDecision(.dismissed, sourceMessageID: "gmail:account-a:message-1")
        _ = first.removeAccount(EmailAccount(
            provider: .gmail,
            providerAccountID: "account-a",
            email: "person@example.com",
            displayName: "Person"
        ))

        let restored = EmailScanHistoryStore(directory: directory)
        restored.load(ownerID: "owner")
        XCTAssertEqual(restored.resolvedTaskMessageIDs, ["gmail:account-a:message-1"])
    }

    func testBackloggedBatchRecordsIDsWithoutAdvancingCursor() {
        let directory = temporaryTestDirectory("email-backlog")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = EmailScanHistoryStore(directory: directory)
        history.load(ownerID: "owner")
        let message = emailMessage(id: "gmail:account-a:message-41")

        XCTAssertTrue(history.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [message],
            jobUpdates: [],
            cursorDate: nil
        ))
        XCTAssertEqual(history.processedMessageIDs(for: "gmail:account-a"), [message.id])
        XCTAssertNil(history.receivedAfter(for: "gmail:account-a"))

        let exhaustedAt = Date(timeIntervalSince1970: 1_786_435_200)
        XCTAssertTrue(history.recordSuccessfulEmptyScan(
            accountID: "gmail:account-a",
            cursorDate: exhaustedAt
        ))
        XCTAssertEqual(
            history.receivedAfter(for: "gmail:account-a"),
            exhaustedAt.addingTimeInterval(-600)
        )
    }

    func testFailedHistoryWriteRollsBackProcessedState() throws {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-history-blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let history = EmailScanHistoryStore(
            directory: blockingFile.appendingPathComponent("child", isDirectory: true)
        )
        history.load(ownerID: "owner")
        let message = emailMessage(id: "gmail:account-a:message-1")

        XCTAssertFalse(history.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [message],
            jobUpdates: [],
            cursorDate: .now
        ))
        XCTAssertTrue(history.processedMessageIDs(for: "gmail:account-a").isEmpty)
        XCTAssertNil(history.receivedAfter(for: "gmail:account-a"))
    }

    func testFailedResetStillStartsAWorkingFullRescanWithoutRepeatingNewIDs() throws {
        let directory = temporaryTestDirectory("email-reset")
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = EmailScanHistoryStore(directory: directory)
        initial.load(ownerID: "owner")
        let old = emailMessage(id: "gmail:account-a:old")
        XCTAssertTrue(initial.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [old],
            jobUpdates: [],
            cursorDate: .now
        ))

        // Replacing the writable directory with a file makes the reset fail.
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        XCTAssertFalse(initial.resetProcessingStateKeepingDecisions())
        XCTAssertNil(initial.receivedAfter(for: "gmail:account-a"))
        XCTAssertTrue(initial.processedMessageIDs(for: "gmail:account-a").isEmpty)

        try FileManager.default.removeItem(at: directory)
        let newlyAnalyzed = emailMessage(id: "gmail:account-a:new")
        XCTAssertTrue(initial.recordSuccessfulAnalysis(
            accountID: "gmail:account-a",
            messages: [newlyAnalyzed],
            jobUpdates: [],
            cursorDate: nil
        ))
        XCTAssertEqual(
            initial.processedMessageIDs(for: "gmail:account-a"),
            [newlyAnalyzed.id]
        )
        XCTAssertNil(initial.receivedAfter(for: "gmail:account-a"))
    }
}

final class GmailIncrementalProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testFortyOneUnseenMessagesReturnsBoundedBatchWithMoreWork() async throws {
        let ids = (1...41).map { "message-\($0)" }
        URLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/messages") == true {
                return try stubResponse(request, json: [
                    "messages": ids.map { ["id": $0, "threadId": "thread-\($0)"] }
                ])
            }
            return try gmailMessageResponse(request)
        }

        let batch = try await gmailTestClient().recentMessageBatch(
            account: testEmailAccount(),
            maxResults: 40,
            token: "token",
            receivedAfter: nil,
            excludingMessageIDs: []
        )

        XCTAssertEqual(batch.messages.count, 40)
        XCTAssertTrue(batch.hasMore)
    }

    func testKnownFirstPageDoesNotHideUnseenMessageOnNextPage() async throws {
        let known = (1...100).map { "known-\($0)" }
        URLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/messages") == true {
                let pageToken = URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first { $0.name == "pageToken" }?.value
                if pageToken == "page-2" {
                    return try stubResponse(request, json: [
                        "messages": [["id": "unseen", "threadId": "thread-unseen"]]
                    ])
                }
                return try stubResponse(request, json: [
                    "messages": known.map { ["id": $0, "threadId": "thread-\($0)"] },
                    "nextPageToken": "page-2"
                ])
            }
            return try gmailMessageResponse(request)
        }
        let account = testEmailAccount()
        let excluded = Set(known.map { "\(account.id):\($0)" })

        let batch = try await gmailTestClient().recentMessageBatch(
            account: account,
            maxResults: 40,
            token: "token",
            receivedAfter: nil,
            excludingMessageIDs: excluded
        )

        XCTAssertEqual(batch.messages.map(\.id), ["\(account.id):unseen"])
        XCTAssertFalse(batch.hasMore)
    }

    func testOneFailedGmailBodyDownloadFailsEntireBatch() async {
        URLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/messages") == true {
                return try stubResponse(request, json: [
                    "messages": [
                        ["id": "good", "threadId": "thread-good"],
                        ["id": "failed", "threadId": "thread-failed"]
                    ]
                ])
            }
            if request.url?.lastPathComponent == "failed" {
                return try stubResponse(
                    request,
                    status: 500,
                    json: ["error": ["message": "Fixture failure"]]
                )
            }
            return try gmailMessageResponse(request)
        }

        do {
            _ = try await gmailTestClient().recentMessageBatch(
                account: testEmailAccount(),
                maxResults: 40,
                token: "token",
                receivedAfter: nil,
                excludingMessageIDs: []
            )
            XCTFail("A partial body download must not advance the scan")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Fixture failure"))
        }
    }

    func testGmailCursorIsEncodedInProviderQuery() async throws {
        let cursor = Date(timeIntervalSince1970: 1_786_435_200)
        URLProtocolStub.handler = { request in
            let query = URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems?.first { $0.name == "q" }?.value
            XCTAssertTrue(query?.contains("after:1786435200") == true)
            return try stubResponse(request, json: ["messages": []])
        }

        let batch = try await gmailTestClient().recentMessageBatch(
            account: testEmailAccount(),
            maxResults: 40,
            token: "token",
            receivedAfter: cursor,
            excludingMessageIDs: []
        )

        XCTAssertTrue(batch.messages.isEmpty)
        XCTAssertFalse(batch.hasMore)
    }
}

final class OutlookIncrementalProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testKnownGraphPageDoesNotHideNextPageAndRequestsImmutableIDs() async throws {
        let known = (1...100).map { "known-\($0)" }
        URLProtocolStub.handler = { request in
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Prefer")?.contains("IdType=\"ImmutableId\"") == true
            )
            if request.url?.path == "/page-2" {
                return try stubResponse(request, json: [
                    "value": [outlookMessageJSON(id: "unseen")]
                ])
            }
            let filter = URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems?.first { $0.name == "$filter" }?.value
            XCTAssertTrue(filter?.contains("receivedDateTime ge") == true)
            return try stubResponse(request, json: [
                "value": known.map { outlookMessageJSON(id: $0) },
                "@odata.nextLink": "https://graph.test/page-2"
            ])
        }
        let account = EmailAccount(
            provider: .outlook,
            providerAccountID: "account-a",
            email: "person@example.com",
            displayName: "Person"
        )
        let excluded = Set(known.map { "\(account.id):\($0)" })

        let batch = try await outlookTestClient().recentMessageBatch(
            account: account,
            maxResults: 40,
            token: "token",
            receivedAfter: Date(timeIntervalSince1970: 1_786_000_000),
            excludingMessageIDs: excluded
        )

        XCTAssertEqual(batch.messages.map(\.id), ["\(account.id):unseen"])
        XCTAssertFalse(batch.hasMore)
    }

    func testRepeatedGraphNextLinkFailsInsteadOfLoopingForever() async {
        URLProtocolStub.handler = { request in
            try stubResponse(request, json: [
                "value": [],
                "@odata.nextLink": request.url?.absoluteString ?? "https://graph.test/messages"
            ])
        }

        do {
            _ = try await outlookTestClient().recentMessageBatch(
                account: EmailAccount(
                    provider: .outlook,
                    providerAccountID: "account-a",
                    email: "person@example.com",
                    displayName: "Person"
                ),
                maxResults: 40,
                token: "token",
                receivedAfter: nil,
                excludingMessageIDs: []
            )
            XCTFail("A repeated Graph page must fail safely")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("repeated page"))
        }
    }
}

final class AIModelPreferenceTests: XCTestCase {
    func testTextAndRealtimeSelectionsPersistIndependently() throws {
        let suiteName = "AIModelPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gpt-5.6-sol", forKey: AppConfig.openAIModelPreferenceKey)
        defaults.set("gpt-realtime-2.1-mini", forKey: AppConfig.openAIRealtimeModelPreferenceKey)

        XCTAssertEqual(AppConfig.selectedOpenAIModel(defaults: defaults), "gpt-5.6-sol")
        XCTAssertEqual(
            AppConfig.selectedOpenAIRealtimeModel(defaults: defaults),
            "gpt-realtime-2.1-mini"
        )
    }

    func testUnknownConfiguredModelRemainsAvailable() {
        let choices = AppConfig.textModelChoices(including: "organization-custom-model")

        XCTAssertEqual(choices.first?.id, "organization-custom-model")
        XCTAssertTrue(choices.contains { $0.id == "gpt-5.6-terra" })
    }

    func testMissingOrWhitespacePreferencesUseBundledFallbacks() throws {
        let suiteName = "AIModelFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppConfig.selectedOpenAIModel(defaults: defaults), AppConfig.bundledOpenAIModel)
        XCTAssertEqual(
            AppConfig.selectedOpenAIRealtimeModel(defaults: defaults),
            AppConfig.bundledOpenAIRealtimeModel
        )
        defaults.set("   ", forKey: AppConfig.openAIModelPreferenceKey)
        defaults.set("\n", forKey: AppConfig.openAIRealtimeModelPreferenceKey)
        XCTAssertEqual(AppConfig.selectedOpenAIModel(defaults: defaults), AppConfig.bundledOpenAIModel)
        XCTAssertEqual(
            AppConfig.selectedOpenAIRealtimeModel(defaults: defaults),
            AppConfig.bundledOpenAIRealtimeModel
        )
    }

    func testResponsesPayloadUsesSelectedModelAndPreservesStrictSchema() throws {
        let schema = OpenAIClient.JSONSchema(
            name: "fixture",
            value: [
                "type": "object",
                "additionalProperties": false,
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ]
        )
        let payload = OpenAIClient(apiKey: "test", model: "gpt-5.6-terra")
            .requestPayload(
                system: "System",
                user: "User",
                schema: schema,
                maxOutputTokens: 321,
                reasoningEffort: .low
            )

        XCTAssertEqual(payload["model"] as? String, "gpt-5.6-terra")
        XCTAssertEqual(payload["store"] as? Bool, false)
        XCTAssertEqual(payload["max_output_tokens"] as? Int, 321)
        let text = try XCTUnwrap(payload["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "fixture")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let reasoning = try XCTUnwrap(payload["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "low")

        let compatibilityPayload = OpenAIClient(apiKey: "test", model: "gpt-4o-mini")
            .requestPayload(
                system: "System",
                user: "User",
                reasoningEffort: .low
            )
        XCTAssertNil(compatibilityPayload["reasoning"])

        let assistantPayload = OpenAIClient(apiKey: "test", model: "gpt-5.6-luna")
            .requestPayload(
                system: "System",
                user: "User",
                reasoningEffort: .medium
            )
        let assistantReasoning = try XCTUnwrap(assistantPayload["reasoning"] as? [String: Any])
        XCTAssertEqual(assistantReasoning["effort"] as? String, "medium")
    }
}

final class WatchTaskSyncProtocolTests: XCTestCase {
    func testSnapshotRoundTripsWithTaskDetails() throws {
        let task = WatchTaskSnapshotItem(
            id: UUID(),
            title: "Call recruiter",
            notes: "Ask about next steps",
            dueDate: Date(timeIntervalSince1970: 1_786_438_800),
            priority: .high,
            updatedAt: Date(timeIntervalSince1970: 1_786_435_200)
        )
        let snapshot = WatchTaskSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_786_435_300),
            tasks: [task]
        )

        let context = try WatchTaskSyncProtocol.context(for: snapshot)

        XCTAssertEqual(WatchTaskSyncProtocol.snapshot(from: context), snapshot)
    }

    func testCompletionMessageRequiresAnExplicitCompletedValue() {
        let id = UUID()

        XCTAssertEqual(
            WatchTaskSyncProtocol.completedTaskID(
                from: WatchTaskSyncProtocol.completionMessage(taskID: id)
            ),
            id
        )
        XCTAssertNil(WatchTaskSyncProtocol.completedTaskID(from: [
            WatchTaskSyncProtocol.completedTaskIDKey: id.uuidString,
            WatchTaskSyncProtocol.completedValueKey: false
        ]))
    }
}

final class HealthAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 28,
            hour: 12
        ))!
    }

    func testBodyLoadCollectsUntilTwoCoreSignalsHaveBaselineCoverage() {
        let summary = HealthSummary(
            metrics: [],
            isConnected: true,
            metricSeries: [series(.heartRateVariability, baseline: 65, current: 48)]
        )

        let estimate = summary.analytics(relativeTo: now, calendar: calendar).bodyLoad

        XCTAssertEqual(estimate.level, .collecting)
        XCTAssertNil(estimate.index)
        XCTAssertNil(estimate.confidence)
    }

    func testBodyLoadIsHigherWhenCoreSignalsMoveAbovePersonalVariation() throws {
        let summary = HealthSummary(
            metrics: [],
            isConnected: true,
            metricSeries: [
                series(.heartRateVariability, baseline: 68, current: 43),
                series(.restingHeartRate, baseline: 51, current: 68),
                series(.respiratoryRate, baseline: 13.5, current: 17.2)
            ]
        )

        let estimate = summary.analytics(relativeTo: now, calendar: calendar).bodyLoad

        XCTAssertEqual(estimate.level, .higherThanUsual)
        XCTAssertGreaterThan(try XCTUnwrap(estimate.index), 58)
        XCTAssertEqual(estimate.factors.count, 3)
        XCTAssertTrue(estimate.factors.allSatisfy { $0.state == .addsLoad })
    }

    func testBodyLoadStaysNearBaselineForTypicalCoreSignals() throws {
        let summary = HealthSummary(
            metrics: [],
            isConnected: true,
            metricSeries: [
                series(.heartRateVariability, baseline: 62, current: 62),
                series(.restingHeartRate, baseline: 53, current: 53),
                series(.respiratoryRate, baseline: 14, current: 14)
            ]
        )

        let estimate = summary.analytics(relativeTo: now, calendar: calendar).bodyLoad

        XCTAssertEqual(estimate.level, .typical)
        XCTAssertEqual(try XCTUnwrap(estimate.index), 50)
        XCTAssertTrue(estimate.factors.allSatisfy { $0.state == .nearBaseline })
    }

    func testBodyLoadDoesNotCountYesterdayCurrentSampleInItsOwnBaseline() throws {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let older = (-8 ... -2).map { offset in
            HealthTrendPoint(
                date: calendar.date(byAdding: .day, value: offset, to: today)!,
                value: 60
            )
        }
        let current = HealthTrendPoint(date: yesterday, value: 35)
        let hrv = HealthMetricSeries(metric: .heartRateVariability, points: older + [current])
        let resting = HealthMetricSeries(metric: .restingHeartRate, points: older.map {
            HealthTrendPoint(date: $0.date, value: 52)
        } + [HealthTrendPoint(date: yesterday, value: 67)])
        let summary = HealthSummary(metrics: [], isConnected: true, metricSeries: [hrv, resting])

        let estimate = summary.analytics(relativeTo: now, calendar: calendar).bodyLoad

        XCTAssertEqual(try XCTUnwrap(estimate.factors.first { $0.id == "hrv" }).baselineDays, 7)
        XCTAssertEqual(try XCTUnwrap(estimate.factors.first { $0.id == "resting-heart" }).baselineDays, 7)
    }

    func testOverallTrendUsesTwoCompletedWeeksAndIgnoresPartialToday() throws {
        let today = calendar.startOfDay(for: now)
        let previous = (-14 ... -8).map {
            HealthTrendPoint(date: calendar.date(byAdding: .day, value: $0, to: today)!, value: 5_000)
        }
        let recent = (-7 ... -1).map {
            HealthTrendPoint(date: calendar.date(byAdding: .day, value: $0, to: today)!, value: 7_500)
        }
        let partialToday = HealthTrendPoint(date: now, value: 10)
        let summary = HealthSummary(
            metrics: [],
            isConnected: true,
            stepTrend: previous + recent + [partialToday]
        )

        let trend = summary.analytics(relativeTo: now, calendar: calendar).overallTrend
        let steps = try XCTUnwrap(trend.comparisons.first { $0.title == "Steps" })

        XCTAssertEqual(trend.direction, .upward)
        XCTAssertEqual(steps.currentAverage, 7_500, accuracy: 0.001)
        XCTAssertEqual(steps.previousAverage, 5_000, accuracy: 0.001)
        XCTAssertEqual(steps.percentChange, 50, accuracy: 0.001)
    }

    func testSleepEfficiencyRequiresValidInBedCoverage() throws {
        let valid = sleepNight(asleep: 7 * 3_600, inBed: 8 * 3_600)
        let missing = sleepNight(asleep: 7 * 3_600, inBed: nil)
        let impossible = sleepNight(asleep: 8 * 3_600, inBed: 7 * 3_600)

        XCTAssertEqual(try XCTUnwrap(valid.efficiency), 87.5, accuracy: 0.001)
        XCTAssertNil(missing.efficiency)
        XCTAssertNil(impossible.efficiency)
    }

    func testMetricSeriesRangeFilteringIsBoundedAndSorted() {
        let today = calendar.startOfDay(for: now)
        let series = HealthMetricSeries(metric: .heartRate, points: [
            HealthTrendPoint(date: now, value: 61),
            HealthTrendPoint(date: calendar.date(byAdding: .day, value: -8, to: today)!, value: 64),
            HealthTrendPoint(date: calendar.date(byAdding: .day, value: -2, to: today)!, value: 62)
        ])

        let todayPoints = series.points(for: .today, relativeTo: now, calendar: calendar)
        let weekPoints = series.points(for: .sevenDays, relativeTo: now, calendar: calendar)

        XCTAssertEqual(todayPoints.map(\.value), [61])
        XCTAssertEqual(weekPoints.map(\.value), [62, 61])
    }

    func testHealthPreviewFixtureExercisesTrendsLoadAndSleepDeepDive() {
        let analytics = MockData.health.analytics()

        XCTAssertFalse(MockData.health.metricSeries.isEmpty)
        XCTAssertEqual(MockData.health.sleepHistory.count, 29)
        XCTAssertTrue(analytics.bodyLoad.isAvailable)
        XCTAssertTrue(analytics.overallTrend.hasComparison)
        XCTAssertFalse(MockData.health.sleepHistory.last?.stageSegments.isEmpty ?? true)
    }

#if canImport(HealthKit)
    func testActivitySummaryComponentsCarryRequiredCalendarAndTimeZone() {
        let components = HealthKitProvider.activitySummaryDayComponents(
            for: now,
            timeZone: calendar.timeZone
        )

        XCTAssertNotNil(components.calendar)
        XCTAssertEqual(components.timeZone, calendar.timeZone)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 28)
        _ = HKQuery.predicate(
            forActivitySummariesBetweenStart: components,
            end: components
        )
    }
#endif

    private func series(
        _ metric: HealthTrendMetric,
        baseline: Double,
        current: Double
    ) -> HealthMetricSeries {
        let today = calendar.startOfDay(for: now)
        let baselinePoints = (-10 ... -1).map { offset in
            HealthTrendPoint(
                date: calendar.date(byAdding: .day, value: offset, to: today)!,
                value: baseline + Double(offset % 3) * 0.1
            )
        }
        return HealthMetricSeries(
            metric: metric,
            points: baselinePoints + [HealthTrendPoint(date: now, value: current)]
        )
    }

    private func sleepNight(asleep: TimeInterval, inBed: TimeInterval?) -> HealthSleepNight {
        let start = now.addingTimeInterval(-(inBed ?? asleep))
        return HealthSleepNight(
            sleepDay: calendar.startOfDay(for: now),
            startDate: start,
            endDate: now,
            asleepDuration: asleep,
            inBedDuration: inBed,
            awakeDuration: max(0, (inBed ?? asleep) - asleep),
            remDuration: asleep * 0.2,
            coreDuration: asleep * 0.65,
            deepDuration: asleep * 0.15,
            unspecifiedDuration: 0,
            awakenings: 0,
            stageSegments: []
        )
    }
}

private func decimal(_ value: String) -> Decimal {
    guard let value = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
        XCTFail("Invalid test decimal: \(value)")
        return 0
    }
    return value
}

private func jsonString(_ value: String) -> Data {
    Data("\"\(value)\"".utf8)
}

private func temporaryTestDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("orbit-\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

private func emailMessage(
    id: String,
    receivedAt: Date = .now
) -> EmailMessage {
    EmailMessage(
        id: id,
        provider: .gmail,
        accountID: "gmail:account-a",
        accountEmail: "person@example.com",
        threadID: "gmail:account-a:thread-1",
        senderName: "Recruiter",
        senderEmail: "recruiter@example.com",
        subject: "Interview update",
        preview: "Choose a time.",
        body: "Choose an interview time.",
        receivedDate: receivedAt,
        isRead: false,
        providerImportance: "high"
    )
}

private func jobUpdate(sourceMessageID: String) -> DetectedJobUpdate {
    DetectedJobUpdate(
        company: "Example Co",
        role: "iOS Engineer",
        status: .interview,
        nextAction: "Choose an interview time",
        reason: "The recruiter requested availability.",
        sourceMessageID: sourceMessageID,
        sourceProvider: .gmail,
        sourceMailbox: "person@example.com",
        sourceSender: "recruiter@example.com",
        sourceSubject: "Interview update",
        sourceDate: .now
    )
}

private func inboxMessage(id: String, receivedAt: Date) -> InboxMessage {
    InboxMessage(
        id: id,
        provider: .gmail,
        accountID: "gmail:account-a",
        accountEmail: "person@example.com",
        senderName: "Recruiter",
        senderEmail: "recruiter@example.com",
        subject: "Interview update",
        aiSummary: "Choose an interview time.",
        receivedAt: receivedAt,
        importance: .high,
        actionRequired: true,
        section: .needsAction
    )
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func gmailTestClient() -> GmailAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return GmailAPIClient(
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://gmail.test/users/me")!
    )
}

private func testEmailAccount() -> EmailAccount {
    EmailAccount(
        provider: .gmail,
        providerAccountID: "account-a",
        email: "person@example.com",
        displayName: "Person"
    )
}

private func stubResponse(
    _ request: URLRequest,
    status: Int = 200,
    json: Any
) throws -> (HTTPURLResponse, Data) {
    let url = try XCTUnwrap(request.url)
    let response = try XCTUnwrap(HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    ))
    return (response, try JSONSerialization.data(withJSONObject: json))
}

private func gmailMessageResponse(
    _ request: URLRequest
) throws -> (HTTPURLResponse, Data) {
    let id = try XCTUnwrap(request.url?.lastPathComponent)
    return try stubResponse(request, json: [
        "id": id,
        "threadId": "thread-\(id)",
        "internalDate": "1786435200000",
        "payload": ["headers": []]
    ])
}

private func outlookTestClient() -> OutlookMailService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return OutlookMailService(
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://graph.test/messages")!
    )
}

private func outlookMessageJSON(id: String) -> [String: Any] {
    [
        "id": id,
        "conversationId": "thread-\(id)",
        "from": [
            "emailAddress": [
                "name": "Recruiter",
                "address": "recruiter@example.com"
            ]
        ],
        "subject": "Interview update",
        "bodyPreview": "Choose a time.",
        "receivedDateTime": "2026-08-13T12:00:00Z",
        "isRead": false,
        "importance": "high"
    ]
}

import Foundation
import XCTest
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

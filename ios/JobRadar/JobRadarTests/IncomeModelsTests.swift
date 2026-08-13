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
        store.remove()
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

import test from "node:test";
import assert from "node:assert/strict";
import {
  annualPaymentCount,
  buildIncomeOverview,
  classifyIncomeTransactions,
  inferIncomeFrequency,
  normalizedIncomeDescriptor
} from "../src/income.js";
import {
  classifyIncomeTransaction,
  validateIncomeClassificationRequest,
  validateIncomeRequest,
  validateIncomeTransactionID
} from "../src/income-service.js";
import { incomeClassificationSortKey } from "../src/store.js";

function transaction(id, overrides = {}) {
  const value = {
    entityType: "TRANSACTION",
    itemID: "item-1",
    id,
    accountID: "checking-1",
    date: "2026-08-01",
    authorizedDate: null,
    name: "Deposit",
    merchantName: null,
    category: null,
    amount: 100,
    direction: "inflow",
    pending: false,
    currencyCode: "USD",
    updatedAt: "2026-08-09T12:00:00.000Z",
    ...overrides
  };
  if (value.providerCategoryPrimary === "INCOME") {
    if (!("providerCategoryDetailed" in overrides)) value.providerCategoryDetailed = "INCOME_WAGES";
    if (!("providerCategoryConfidence" in overrides)) value.providerCategoryConfidence = "VERY_HIGH";
  }
  return value;
}

function userClassification(target, classification, overrides = {}) {
  return {
    entityType: "INCOME_CLASSIFICATION",
    transactionID: target.id,
    accountID: target.accountID,
    itemID: target.itemID,
    transactionDate: target.date,
    descriptor: normalizedIncomeDescriptor(target),
    classification,
    createdAt: "2026-08-08T12:00:00.000Z",
    updatedAt: "2026-08-08T12:00:00.000Z",
    ...overrides
  };
}

function classifiedByID(records, asOfDate = "2026-08-09") {
  return new Map(classifyIncomeTransactions(records, { asOfDate }).map(entry => [entry.transaction.id, entry]));
}

test("provider income confirms while text-only payroll and unknown deposits require review", () => {
  const providerPayroll = transaction("provider-pay", {
    name: "ACME Payroll",
    amount: 2_000,
    providerCategoryPrimary: "INCOME",
    providerCategoryDetailed: "INCOME_WAGES"
  });
  const keywordOnly = transaction("keyword-pay", { name: "ACME Payroll", amount: 900 });
  const unknown = transaction("unknown", { name: "Mobile deposit", amount: 350 });
  const purchase = transaction("purchase", { direction: "outflow", name: "Groceries", amount: 80 });
  const result = classifiedByID([providerPayroll, keywordOnly, unknown, purchase]);

  assert.equal(result.get("provider-pay").status, "confirmed");
  assert.equal(result.get("provider-pay").reason, "providerIncomeCategory");
  assert.equal(result.get("provider-pay").sourceType, "salary");
  assert.equal(result.get("keyword-pay").status, "needsReview");
  assert.equal(result.get("keyword-pay").reason, "incomeKeyword");
  assert.equal(result.get("unknown").status, "needsReview");
  assert.equal(result.has("purchase"), false);
});

test("low-confidence and nonspecific provider income categories remain review items", () => {
  const lowConfidenceWages = transaction("low-wages", {
    name: "Employer deposit",
    providerCategoryPrimary: "INCOME",
    providerCategoryDetailed: "INCOME_WAGES",
    providerCategoryConfidence: "LOW"
  });
  const vagueIncome = transaction("vague-income", {
    name: "Miscellaneous deposit",
    providerCategoryPrimary: "INCOME",
    providerCategoryDetailed: "INCOME_OTHER_INCOME",
    providerCategoryConfidence: "VERY_HIGH"
  });
  const result = classifiedByID([lowConfidenceWages, vagueIncome]);

  assert.equal(result.get("low-wages").status, "needsReview");
  assert.equal(result.get("vague-income").status, "needsReview");
});

test("confirmed pending income is separate from posted income and ambiguous pending inflows", () => {
  const records = [
    transaction("posted", {
      amount: 1_000,
      providerCategoryPrimary: "INCOME",
      providerCategoryDetailed: "INCOME_WAGES"
    }),
    transaction("pending-income", {
      amount: 1_200,
      pending: true,
      providerCategoryPrimary: "INCOME",
      providerCategoryDetailed: "INCOME_WAGES"
    }),
    transaction("pending-review", { amount: 225, pending: true, name: "Mystery ACH credit" })
  ];
  const summary = buildIncomeOverview(records, { asOfDate: "2026-08-09" }).summaries[0];

  assert.deepEqual(summary.thisMonth, { confirmed: 1_000, pending: 1_200, needsReview: 225 });
  assert.equal(summary.yearToDate, 1_000);
  assert.equal(summary.confirmedTransactions.length, 2);
  assert.equal(summary.confirmedTransactions.find(value => value.id === "pending-income").pending, true);
  assert.equal(summary.needsReviewTransactions[0].classification, "needsReview");
});

test("refunds, reversals, reimbursements, and loan proceeds never auto-count as income", () => {
  const values = [
    transaction("refund", {
      name: "Card purchase refund",
      providerCategoryPrimary: "INCOME",
      providerCategoryDetailed: "INCOME_OTHER_INCOME"
    }),
    transaction("reversal", { name: "ACH reversal" }),
    transaction("reimbursement", { name: "Travel expense reimbursement" }),
    transaction("loan", {
      name: "Loan funding",
      providerCategoryPrimary: "TRANSFER_IN",
      providerCategoryDetailed: "TRANSFER_IN_CASH_ADVANCES_AND_LOANS"
    })
  ];
  const result = classifiedByID(values);

  assert.equal(result.get("refund").reason, "refundOrReversal");
  assert.equal(result.get("reversal").reason, "refundOrReversal");
  assert.equal(result.get("reimbursement").reason, "reimbursement");
  assert.equal(result.get("loan").reason, "loanProceeds");
  for (const entry of result.values()) assert.equal(entry.status, "excluded");
});

test("P2P deposits require review while a reconciled own-account transfer is excluded", () => {
  const p2p = transaction("venmo", {
    name: "Venmo payment from Taylor",
    providerCategoryPrimary: "TRANSFER_IN",
    providerCategoryDetailed: "TRANSFER_IN_ACCOUNT_TRANSFER"
  });
  const transferIn = transaction("transfer-in", {
    accountID: "savings-1",
    date: "2026-08-03",
    name: "Online transfer from checking",
    amount: 500
  });
  const transferOut = transaction("transfer-out", {
    accountID: "checking-1",
    date: "2026-08-02",
    name: "Online transfer to savings",
    amount: 500,
    direction: "outflow"
  });
  const equalButUnrelated = transaction("unrelated", {
    accountID: "checking-2",
    date: "2026-08-02",
    name: "Mystery deposit",
    amount: 700
  });
  const equalPurchase = transaction("equal-purchase", {
    accountID: "checking-1",
    date: "2026-08-02",
    name: "Furniture",
    amount: 700,
    direction: "outflow"
  });
  const result = classifiedByID([p2p, transferIn, transferOut, equalButUnrelated, equalPurchase]);

  assert.equal(result.get("venmo").status, "needsReview");
  assert.equal(result.get("venmo").reason, "peerToPeer");
  assert.equal(result.get("transfer-in").status, "excluded");
  assert.equal(result.get("transfer-in").reason, "ownAccountTransfer");
  assert.equal(result.get("unrelated").status, "needsReview");
});

test("multiple possible transfer counterparts remain reviewable instead of guessing ownership", () => {
  const inflow = transaction("ambiguous-in", {
    accountID: "savings-1",
    name: "Online transfer",
    amount: 900
  });
  const firstOutflow = transaction("possible-out-1", {
    accountID: "checking-1",
    name: "Online transfer",
    amount: 900,
    direction: "outflow"
  });
  const secondOutflow = transaction("possible-out-2", {
    accountID: "checking-2",
    name: "Online transfer",
    amount: 900,
    direction: "outflow"
  });
  const result = classifiedByID([inflow, firstOutflow, secondOutflow]);

  assert.equal(result.get("ambiguous-in").status, "needsReview");
  assert.equal(result.get("ambiguous-in").reason, "ambiguousTransfer");

  const firstInflow = transaction("possible-in-1", {
    accountID: "savings-1",
    name: "Online transfer",
    amount: 450
  });
  const secondInflow = transaction("possible-in-2", {
    accountID: "savings-2",
    name: "Online transfer",
    amount: 450
  });
  const onlyOutflow = transaction("only-out", {
    accountID: "checking-1",
    name: "Online transfer",
    amount: 450,
    direction: "outflow"
  });
  const reverseResult = classifiedByID([firstInflow, secondInflow, onlyOutflow]);
  assert.equal(reverseResult.get("possible-in-1").reason, "ambiguousTransfer");
  assert.equal(reverseResult.get("possible-in-2").reason, "ambiguousTransfer");
});

test("individual overrides win and exact normalized descriptors safely carry future rules", () => {
  const first = transaction("first", {
    name: "ACME PAY 123456789",
    paymentChannel: "ach",
    amount: 1_500
  });
  const individualException = transaction("exception", {
    name: "acme-pay 777777777",
    paymentChannel: "ACH",
    amount: 20
  });
  const future = transaction("future", {
    date: "2026-08-08",
    name: "Acme Pay 999999999",
    paymentChannel: "ach",
    amount: 1_510
  });
  assert.equal(normalizedIncomeDescriptor(first), normalizedIncomeDescriptor(future));

  const excludeException = userClassification(individualException, "notIncome", {
    updatedAt: "2026-08-07T12:00:00.000Z"
  });
  const confirmPattern = userClassification(first, "income", {
    sourceName: "Acme",
    sourceType: "contract",
    updatedAt: "2026-08-08T12:00:00.000Z"
  });
  const result = classifiedByID([first, individualException, future, excludeException, confirmPattern]);

  assert.equal(result.get("first").reason, "userOverride");
  assert.equal(result.get("exception").status, "excluded");
  assert.equal(result.get("exception").reason, "userOverride");
  assert.equal(result.get("future").status, "confirmed");
  assert.equal(result.get("future").reason, "userDescriptorRule");
  assert.equal(result.get("future").sourceName, "Acme");
  assert.equal(result.get("future").sourceType, "contract");
});

test("descriptor rules apply forward in time without rewriting earlier ambiguous history", () => {
  const earlier = transaction("earlier", { date: "2026-07-01", name: "Studio ACH 123456" });
  const confirmed = transaction("confirmed", { date: "2026-08-01", name: "studio ach 777777" });
  const future = transaction("later", { date: "2026-08-08", name: "STUDIO ACH 999999" });
  const rule = userClassification(confirmed, "income", { sourceName: "Studio", sourceType: "freelance" });
  const result = classifiedByID([earlier, confirmed, future, rule]);

  assert.equal(result.get("earlier").status, "needsReview");
  assert.equal(result.get("confirmed").reason, "userOverride");
  assert.equal(result.get("later").reason, "userDescriptorRule");
});

test("confirmed P2P descriptors can identify later matching income while unrelated P2P stays review", () => {
  const consulting = transaction("venmo-consulting", { date: "2026-08-01", name: "Venmo Taylor consulting" });
  const futureConsulting = transaction("venmo-future", { date: "2026-08-08", name: "venmo taylor consulting" });
  const unrelated = transaction("venmo-gift", { date: "2026-08-08", name: "Venmo Morgan" });
  const rule = userClassification(consulting, "income", { sourceName: "Taylor", sourceType: "consulting" });
  const result = classifiedByID([consulting, futureConsulting, unrelated, rule]);

  assert.equal(result.get("futureConsulting"), undefined);
  assert.equal(result.get("venmo-future").status, "confirmed");
  assert.equal(result.get("venmo-future").reason, "userDescriptorRule");
  assert.equal(result.get("venmo-gift").status, "needsReview");
});

test("a confirmed exact descriptor can recognize later employer deposits labeled as transfers", () => {
  const first = transaction("transfer-pay-1", {
    date: "2026-08-01",
    name: "ACME contract ACH",
    providerCategoryPrimary: "TRANSFER_IN",
    providerCategoryDetailed: "TRANSFER_IN_DEPOSIT"
  });
  const future = transaction("transfer-pay-2", {
    date: "2026-08-08",
    name: "ACME contract ACH",
    providerCategoryPrimary: "TRANSFER_IN",
    providerCategoryDetailed: "TRANSFER_IN_DEPOSIT"
  });
  const rule = userClassification(first, "income", { sourceName: "ACME", sourceType: "contract" });
  const result = classifiedByID([first, future, rule]);

  assert.equal(result.get("first"), undefined);
  assert.equal(result.get("transfer-pay-1").reason, "userOverride");
  assert.equal(result.get("transfer-pay-2").reason, "userDescriptorRule");
});

test("a pending transaction override follows Plaid's posted replacement ID", () => {
  const pending = transaction("pending-old", { name: "Client ACH", pending: true, date: "2026-08-01" });
  const posted = transaction("posted-new", {
    name: "Client ACH posted",
    pendingTransactionID: "pending-old",
    date: "2026-08-03",
    amount: 750
  });
  const rule = userClassification(pending, "income", { sourceName: "Client", sourceType: "consulting" });
  const result = classifiedByID([posted, rule]);

  assert.equal(result.get("posted-new").status, "confirmed");
  assert.equal(result.get("posted-new").reason, "userOverride");
  assert.equal(result.get("posted-new").sourceName, "Client");
});

test("learned exclusions carry forward and automated hard exclusions beat inherited positive rules", () => {
  const gift = transaction("gift-1", { name: "Family deposit 123456" });
  const futureGift = transaction("gift-2", { name: "family deposit 999999", date: "2026-08-08" });
  const loan = transaction("loan-1", { name: "Loan proceeds 123456", amount: 5_000 });
  const futureLoan = transaction("loan-2", { name: "loan proceeds 999999", amount: 5_000, date: "2026-08-08" });
  const rules = [
    userClassification(gift, "notIncome"),
    userClassification(loan, "income", { sourceName: "Side business", sourceType: "business" })
  ];
  const result = classifiedByID([gift, futureGift, loan, futureLoan, ...rules]);

  assert.equal(result.get("gift-1").status, "excluded");
  assert.equal(result.get("gift-2").status, "excluded");
  assert.equal(result.get("gift-2").reason, "userDescriptorRule");
  assert.equal(result.get("loan-1").status, "confirmed");
  assert.equal(result.get("loan-1").reason, "userOverride");
  assert.equal(result.get("loan-2").status, "excluded");
  assert.equal(result.get("loan-2").reason, "loanProceeds");
});

test("posted date controls month and YTD while authorized date remains output context", () => {
  const records = [
    transaction("august", {
      date: "2026-08-01",
      authorizedDate: "2026-07-31",
      amount: 600,
      providerCategoryPrimary: "INCOME"
    }),
    transaction("july", {
      date: "2026-07-31",
      authorizedDate: "2026-08-01",
      amount: 400,
      providerCategoryPrimary: "INCOME"
    }),
    transaction("december", {
      date: "2025-12-31",
      amount: 300,
      providerCategoryPrimary: "INCOME"
    }),
    transaction("future", {
      date: "2026-08-10",
      amount: 9_999,
      providerCategoryPrimary: "INCOME"
    })
  ];
  const summary = buildIncomeOverview(records, { asOfDate: "2026-08-09" }).summaries[0];

  assert.equal(summary.thisMonth.confirmed, 600);
  assert.equal(summary.lastMonth.confirmed, 400);
  assert.equal(summary.yearToDate, 1_000);
  assert.equal(summary.changeAmount, 200);
  assert.equal(summary.changePercent, 50);
  assert.equal(summary.confirmedTransactions.find(value => value.id === "august").authorizedDate, "2026-07-31");
  assert.equal(summary.confirmedTransactions.some(value => value.id === "future"), false);
  assert.equal(summary.history.find(value => value.month === "2026-07").confirmed, 400);
});

test("zero previous-month income yields a finite change and null percentage", () => {
  const summary = buildIncomeOverview([
    transaction("current", { amount: 250, providerCategoryPrimary: "INCOME" })
  ], { asOfDate: "2026-08-09" }).summaries[0];

  assert.equal(summary.changeAmount, 250);
  assert.equal(summary.changePercent, null);
  assert.equal(JSON.stringify(summary).includes("Infinity"), false);
});

test("income is grouped by currency and unlike currencies are never added together", () => {
  const overview = buildIncomeOverview([
    transaction("usd", { amount: 1_000, currencyCode: "USD", providerCategoryPrimary: "INCOME" }),
    transaction("eur", { amount: 800, currencyCode: "eur", providerCategoryPrimary: "INCOME" }),
    {
      entityType: "ACCOUNT",
      id: "gbp-account",
      accountID: "gbp-account",
      currencyCode: "GBP",
      updatedAt: "2026-08-09T11:00:00.000Z"
    }
  ], { asOfDate: "2026-08-09" });

  assert.deepEqual(overview.summaries.map(value => value.currencyCode), ["EUR", "GBP", "USD"]);
  assert.equal(overview.summaries.find(value => value.currencyCode === "USD").thisMonth.confirmed, 1_000);
  assert.equal(overview.summaries.find(value => value.currencyCode === "EUR").thisMonth.confirmed, 800);
  assert.equal(overview.summaries.find(value => value.currencyCode === "GBP").thisMonth.confirmed, 0);
  assert.equal(overview.summaries.find(value => value.currencyCode === "GBP").coverage.startDate, null);
  assert.equal(overview.summaries.some(value => value.thisMonth.confirmed === 1_800), false);
});

test("the summary consumes all stored transactions rather than a recent-activity slice", () => {
  const records = Array.from({ length: 75 }, (_, index) => transaction(`pay-${index}`, {
    amount: 10,
    providerCategoryPrimary: "INCOME",
    providerCategoryDetailed: "INCOME_WAGES"
  }));
  records.push({ entityType: "PLAID_ITEM", accessTokenCiphertext: "never-return-this", userSub: "secret-user" });
  const overview = buildIncomeOverview(records, { asOfDate: "2026-08-09" });
  const serialized = JSON.stringify(overview);

  assert.equal(overview.summaries[0].thisMonth.confirmed, 750);
  assert.equal(overview.summaries[0].confirmedTransactions.length, 75);
  assert.doesNotMatch(serialized, /never-return-this|secret-user|accessTokenCiphertext|\"PK\"|\"SK\"/);
});

test("frequency inference and annual conversions use 52, 26, 24, and 12 periods", () => {
  assert.equal(inferIncomeFrequency(["2026-07-17", "2026-07-24", "2026-07-31", "2026-08-07"]), "weekly");
  assert.equal(inferIncomeFrequency(["2026-06-12", "2026-06-26", "2026-07-10", "2026-07-24", "2026-08-07"]), "biweekly");
  assert.equal(inferIncomeFrequency(["2026-06-01", "2026-06-15", "2026-07-01", "2026-07-15", "2026-08-01"]), "semimonthly");
  assert.equal(inferIncomeFrequency([
    "2026-05-01", "2026-05-16", "2026-06-01", "2026-06-16", "2026-07-01", "2026-07-16", "2026-08-01"
  ]), "semimonthly");
  assert.equal(inferIncomeFrequency([
    "2026-05-15", "2026-05-30", "2026-06-15", "2026-06-30", "2026-07-15", "2026-07-30"
  ]), "semimonthly");
  assert.equal(inferIncomeFrequency(["2026-05-07", "2026-06-07", "2026-07-07", "2026-08-07"]), "monthly");
  assert.equal(inferIncomeFrequency(["2026-04-02", "2026-05-19", "2026-08-07"]), "irregular");
  assert.equal(inferIncomeFrequency(["2026-08-07"]), "oneTime");
  assert.deepEqual([
    annualPaymentCount("weekly"),
    annualPaymentCount("biweekly"),
    annualPaymentCount("semimonthly"),
    annualPaymentCount("monthly")
  ], [52, 26, 24, 12]);
});

test("recurring sources expose conservative annualization, next dates, and projections", () => {
  const sourceRecords = (name, amount, dates) => dates.map((date, index) => transaction(`${name}-${index}`, {
    date,
    name,
    amount,
    providerCategoryPrimary: "INCOME"
  }));
  const records = [
    ...sourceRecords("Weekly employer", 100, ["2026-07-17", "2026-07-24", "2026-07-31", "2026-08-07"]),
    ...sourceRecords("Biweekly employer", 200, ["2026-06-12", "2026-06-26", "2026-07-10", "2026-07-24", "2026-08-07"]),
    ...sourceRecords("Semimonthly employer", 300, ["2026-06-01", "2026-06-15", "2026-07-01", "2026-07-15", "2026-08-01"]),
    ...sourceRecords("Monthly client", 400, ["2026-05-07", "2026-06-07", "2026-07-07", "2026-08-07"])
  ];
  const summary = buildIncomeOverview(records, { asOfDate: "2026-08-09" }).summaries[0];
  const byName = new Map(summary.sources.map(source => [source.name, source]));

  assert.equal(byName.get("Weekly employer").frequency, "weekly");
  assert.equal(byName.get("Weekly employer").averageMonthly, 433.333333);
  assert.equal(byName.get("Biweekly employer").frequency, "biweekly");
  assert.equal(byName.get("Semimonthly employer").frequency, "semimonthly");
  assert.equal(byName.get("Monthly client").frequency, "monthly");
  assert.equal(summary.basis, "observedNetDeposit");
  assert.equal(byName.get("Weekly employer").basis, "observedNetDeposit");
  assert.equal(summary.confirmedTransactions[0].basis, "observedNetDeposit");
  assert.equal(summary.estimatedAnnual, 22_400);
  assert.equal(summary.expectedPaychecks.find(value => value.sourceName === "Weekly employer").date, "2026-08-14");
  assert.ok(summary.projectedMonthEnd > summary.thisMonth.confirmed);
  assert.ok(summary.projectedYearEnd > summary.yearToDate);
});

test("two observations are insufficient for projections and monthly dates retain end-of-month cadence", () => {
  const twoPayments = ["2026-07-10", "2026-07-24"].map((date, index) => transaction(`two-${index}`, {
    date,
    name: "New employer",
    amount: 500,
    providerCategoryPrimary: "INCOME"
  }));
  const sparse = buildIncomeOverview(twoPayments, { asOfDate: "2026-07-25" }).summaries[0];
  assert.equal(sparse.sources[0].frequency, "biweekly");
  assert.equal(sparse.estimatedAnnual, null);
  assert.deepEqual(sparse.expectedPaychecks, []);

  const threeSemimonthly = ["2026-06-01", "2026-06-15", "2026-07-01"].map((date, index) =>
    transaction(`three-semi-${index}`, {
      date,
      name: "New semimonthly employer",
      amount: 1_000,
      providerCategoryPrimary: "INCOME"
    }));
  const stillSparse = buildIncomeOverview(threeSemimonthly, { asOfDate: "2026-07-02" }).summaries[0];
  assert.equal(stillSparse.sources[0].frequency, "semimonthly");
  assert.equal(stillSparse.estimatedAnnual, null);
  assert.deepEqual(stillSparse.expectedPaychecks, []);

  const monthEndPayments = ["2026-01-31", "2026-02-28", "2026-03-31"].map((date, index) =>
    transaction(`month-end-${index}`, {
      date,
      name: "Month End Client",
      amount: 1_000,
      providerCategoryPrimary: "INCOME"
    }));
  const monthly = buildIncomeOverview(monthEndPayments, { asOfDate: "2026-04-01" }).summaries[0];
  assert.equal(monthly.sources[0].frequency, "monthly");
  assert.equal(monthly.expectedPaychecks[0].date, "2026-04-30");
});

test("one-time and stale income sources do not produce unsupported guarantees", () => {
  const summary = buildIncomeOverview([
    transaction("bonus", {
      date: "2026-01-02",
      name: "Annual bonus",
      amount: 2_000,
      providerCategoryPrimary: "INCOME"
    })
  ], { asOfDate: "2026-08-09" }).summaries[0];

  assert.equal(summary.sources[0].frequency, "oneTime");
  assert.equal(summary.sources[0].active, false);
  assert.equal(summary.sources[0].nextExpectedPaymentDate, null);
  assert.equal(summary.estimatedAnnual, null);
  assert.equal(summary.projectedMonthEnd, null);
  assert.equal(summary.projectedYearEnd, null);
  assert.deepEqual(summary.expectedPaychecks, []);
});

test("coverage and lastUpdatedAt are explicit without inventing unavailable months", () => {
  const summary = buildIncomeOverview([
    transaction("march", {
      date: "2026-03-14",
      amount: 600,
      providerCategoryPrimary: "INCOME",
      updatedAt: "2026-08-08T12:00:00.000Z"
    }),
    transaction("august", {
      date: "2026-08-01",
      amount: 600,
      providerCategoryPrimary: "INCOME",
      updatedAt: "2026-08-09T13:00:00.000Z"
    })
  ], { asOfDate: "2026-08-09" });

  assert.equal(summary.lastUpdatedAt, "2026-08-09T13:00:00.000Z");
  assert.deepEqual(summary.summaries[0].coverage, {
    startDate: "2026-03-14",
    endDate: "2026-08-09",
    completeMonths: 4
  });
  assert.equal(summary.summaries[0].averageMonthly, 200);
});

test("income request validation rejects impossible dates, invalid zones, and unknown fields", () => {
  assert.deepEqual(validateIncomeRequest({ asOfDate: "2026-08-09", timeZone: "America/Indiana/Indianapolis" }), {
    asOfDate: "2026-08-09",
    timeZone: "America/Indiana/Indianapolis"
  });
  assert.throws(() => validateIncomeRequest({ asOfDate: "2026-02-29", timeZone: "UTC" }), /real calendar date/);
  assert.throws(() => validateIncomeRequest({ asOfDate: "2024-02-29", timeZone: "Mars\/Olympus" }), /valid IANA/);
  assert.throws(() => validateIncomeRequest({ asOfDate: "2026-08-09", timeZone: "UTC", userSub: "attacker" }), /Unknown request field/);
  assert.throws(() => validateIncomeRequest([]), /JSON object/);
});

test("classification validation accepts only exact decisions and bounded source metadata", () => {
  assert.deepEqual(validateIncomeClassificationRequest({
    classification: "income",
    sourceName: "  Acme  ",
    type: "consulting",
    asOfDate: "2026-08-09",
    timeZone: "America/Indiana/Indianapolis"
  }), {
    classification: "income",
    sourceName: "Acme",
    sourceType: "consulting",
    asOfDate: "2026-08-09",
    timeZone: "America/Indiana/Indianapolis"
  });
  assert.deepEqual(validateIncomeClassificationRequest({
    classification: "notIncome",
    sourceType: "other",
    asOfDate: "2026-08-09",
    timeZone: "UTC"
  }), {
    classification: "notIncome",
    sourceName: undefined,
    sourceType: "other",
    asOfDate: "2026-08-09",
    timeZone: "UTC"
  });
  assert.throws(() => validateIncomeClassificationRequest({ classification: "maybe" }), /income or notIncome/);
  assert.throws(() => validateIncomeClassificationRequest({ classification: "income", type: "wages" }), /type must be one of/);
  assert.throws(() => validateIncomeClassificationRequest({
    classification: "income", type: "salary", sourceType: "hourly"
  }), /cannot disagree/);
  assert.throws(() => validateIncomeClassificationRequest({ classification: "income", sourceName: "\n" }), /sourceName/);
  assert.throws(() => validateIncomeClassificationRequest({ classification: "income", userID: "someone-else" }), /Unknown request field/);
  assert.throws(() => validateIncomeClassificationRequest({ classification: "income" }), /asOfDate/);
});

test("transaction IDs and classification storage keys are bounded and opaque", () => {
  assert.equal(validateIncomeTransactionID("plaid_transaction-123"), "plaid_transaction-123");
  assert.throws(() => validateIncomeTransactionID("../another-user"), /valid financial transaction ID/);
  assert.throws(() => validateIncomeTransactionID("a".repeat(129)), /valid financial transaction ID/);
  const key = incomeClassificationSortKey("plaid_transaction-123");
  assert.match(key, /^INCOME_CLASSIFICATION#[a-f0-9]{64}$/);
  assert.doesNotMatch(key, /plaid_transaction/);
});

test("classification service scopes persistence to the authenticated user and returns a refreshed overview", async () => {
  const target = transaction("target-inflow", { name: "Client payment", amount: 875 });
  let captured;
  const overview = await classifyIncomeTransaction("google-user-123", target.id, {
    classification: "income",
    sourceName: "Client",
    type: "consulting",
    asOfDate: "2026-08-09",
    timeZone: "America/Indiana/Indianapolis"
  }, {
    listUserRecords: async userSub => {
      assert.equal(userSub, "google-user-123");
      return [target];
    },
    saveIncomeClassification: async (userSub, savedTransaction, value, existing) => {
      captured = { userSub, savedTransaction, value, existing };
      return {
        entityType: "INCOME_CLASSIFICATION",
        transactionID: savedTransaction.id,
        transactionDate: savedTransaction.date,
        accountID: savedTransaction.accountID,
        itemID: savedTransaction.itemID,
        descriptor: value.descriptor,
        classification: value.classification,
        sourceName: value.sourceName,
        sourceType: value.sourceType,
        updatedAt: "2026-08-09T18:00:00.000Z"
      };
    }
  });

  assert.equal(captured.userSub, "google-user-123");
  assert.equal(captured.savedTransaction.id, "target-inflow");
  assert.equal(captured.value.classification, "income");
  assert.equal(captured.value.sourceName, "Client");
  assert.equal(captured.value.sourceType, "consulting");
  assert.equal(captured.existing, null);
  assert.equal(overview.summaries[0].thisMonth.confirmed, 875);
  assert.equal(overview.summaries[0].confirmedTransactions[0].userConfirmed, true);
  assert.equal(overview.lastUpdatedAt, "2026-08-09T18:00:00.000Z");
});

test("classification service rejects missing and outgoing transactions without writing", async () => {
  let writes = 0;
  const request = {
    classification: "notIncome",
    asOfDate: "2026-08-09",
    timeZone: "UTC"
  };
  const dependencies = records => ({
    listUserRecords: async () => records,
    saveIncomeClassification: async () => { writes += 1; }
  });

  await assert.rejects(
    classifyIncomeTransaction("google-user-123", "missing", request, dependencies([])),
    error => error.statusCode === 404
  );
  await assert.rejects(
    classifyIncomeTransaction("google-user-123", "outgoing", request, dependencies([
      transaction("outgoing", { direction: "outflow" })
    ])),
    error => error.statusCode === 409
  );
  assert.equal(writes, 0);
});

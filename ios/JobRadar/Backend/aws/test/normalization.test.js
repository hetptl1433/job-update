import test from "node:test";
import assert from "node:assert/strict";
import { buildOverview, normalizeAccount, normalizeTransaction } from "../src/normalization.js";

const item = { itemID: "item-1", institutionName: "Orbit Test Bank" };

test("normalizes deposit and credit accounts for the iOS model", () => {
  const checking = normalizeAccount({
    account_id: "checking-1",
    type: "depository",
    subtype: "checking",
    name: "Everyday Checking",
    official_name: null,
    mask: "1234",
    balances: { current: 1500.25, available: 1400, iso_currency_code: "USD" }
  }, item);
  const credit = normalizeAccount({
    account_id: "credit-1",
    type: "credit",
    subtype: "credit card",
    name: "Rewards Card",
    balances: { current: 420.50, available: 4580, iso_currency_code: "USD" }
  }, item);

  assert.equal(checking.kind, "checking");
  assert.equal(checking.currentBalance, 1500.25);
  assert.equal(credit.kind, "creditCard");
  assert.equal(credit.currentBalance, 420.50);
});

test("converts Plaid's amount sign to explicit inflow and outflow", () => {
  const paycheck = normalizeTransaction({
    transaction_id: "pay-1",
    account_id: "checking-1",
    date: "2026-08-01",
    authorized_date: "2026-07-31",
    name: "Payroll",
    amount: -2000,
    pending: false,
    iso_currency_code: "USD",
    payment_channel: "other",
    personal_finance_category: {
      primary: "INCOME",
      detailed: "INCOME_WAGES",
      confidence_level: "VERY_HIGH"
    }
  });
  const groceries = normalizeTransaction({
    transaction_id: "food-1",
    account_id: "checking-1",
    date: "2026-08-02",
    name: "Grocery Store",
    amount: 82.13,
    pending: false,
    iso_currency_code: "USD",
    personal_finance_category: { primary: "FOOD_AND_DRINK" }
  });

  assert.deepEqual([paycheck.direction, paycheck.amount], ["inflow", 2000]);
  assert.equal(paycheck.date, "2026-08-01");
  assert.equal(paycheck.authorizedDate, "2026-07-31");
  assert.equal(paycheck.providerCategoryPrimary, "INCOME");
  assert.equal(paycheck.providerCategoryDetailed, "INCOME_WAGES");
  assert.deepEqual([groceries.direction, groceries.amount], ["outflow", 82.13]);
  assert.equal(groceries.category, "Food And Drink");
});

test("builds compact totals without leaking backend storage fields", () => {
  const timestamp = "2026-08-09T12:00:00.000Z";
  const records = [
    {
      entityType: "PLAID_ITEM",
      itemID: "item-1",
      institutionName: "Orbit Test Bank",
      accessTokenCiphertext: "must-not-leak",
      needsAttention: false,
      updatedAt: timestamp
    },
    {
      entityType: "ACCOUNT",
      ...normalizeAccount({
        account_id: "checking-1",
        type: "depository",
        subtype: "checking",
        name: "Checking",
        balances: { current: 1500, available: 1400, iso_currency_code: "USD" }
      }, item),
      updatedAt: timestamp
    },
    {
      entityType: "ACCOUNT",
      ...normalizeAccount({
        account_id: "credit-1",
        type: "credit",
        subtype: "credit card",
        name: "Card",
        balances: { current: 300, available: 4700, iso_currency_code: "USD" }
      }, item),
      updatedAt: timestamp
    },
    {
      entityType: "TRANSACTION",
      itemID: "item-1",
      ...normalizeTransaction({
        transaction_id: "pay-1",
        account_id: "checking-1",
        date: "2026-08-01",
        name: "Payroll",
        amount: -2000,
        pending: false,
        iso_currency_code: "USD"
      }),
      updatedAt: timestamp
    },
    {
      entityType: "TRANSACTION",
      itemID: "item-1",
      ...normalizeTransaction({
        transaction_id: "pending-1",
        account_id: "checking-1",
        date: "2026-08-03",
        name: "Pending purchase",
        amount: 50,
        pending: true,
        iso_currency_code: "USD"
      }),
      updatedAt: timestamp
    }
  ];

  const overview = buildOverview(records, new Date("2026-08-09T15:00:00Z"));
  assert.equal(overview.monthlyInflow, 2000);
  assert.equal(overview.monthlyOutflow, 0);
  assert.equal(overview.totalCash, 1500);
  assert.equal(overview.totalCreditBalance, 300);
  assert.equal(overview.institutions[0].accountCount, 2);
  assert.equal("accessTokenCiphertext" in overview.institutions[0], false);
});

test("returns every stored transaction for the all-transactions screen", () => {
  const records = Array.from({ length: 75 }, (_, index) => ({
    entityType: "TRANSACTION",
    itemID: "item-1",
    ...normalizeTransaction({
      transaction_id: `transaction-${index}`,
      account_id: "checking-1",
      date: "2026-08-01",
      name: `Transaction ${String(index).padStart(2, "0")}`,
      amount: index + 1,
      pending: false,
      iso_currency_code: "USD"
    })
  }));

  const overview = buildOverview(records, new Date("2026-08-09T15:00:00Z"));

  assert.equal(overview.recentTransactions.length, 75);
});

test("detects active recurring payments and normalizes them to a monthly total", () => {
  const dates = ["2026-05-05", "2026-06-05", "2026-07-05", "2026-08-05"];
  const records = dates.map((date, index) => ({
    entityType: "TRANSACTION",
    itemID: "item-1",
    ...normalizeTransaction({
      transaction_id: `stream-${index}`,
      account_id: "credit-1",
      date,
      name: "STREAMFLIX SUBSCRIPTION 483920",
      merchant_name: "Streamflix",
      amount: 15.99,
      pending: false,
      iso_currency_code: "USD",
      personal_finance_category: { primary: "ENTERTAINMENT" }
    })
  }));

  const overview = buildOverview(records, new Date("2026-08-11T12:00:00Z"));

  assert.equal(overview.recurringPayments.length, 1);
  assert.equal(overview.recurringPayments[0].name, "Streamflix");
  assert.equal(overview.recurringPayments[0].cadence, "monthly");
  assert.equal(overview.recurringPayments[0].amount, 15.99);
  assert.equal(overview.recurringPayments[0].monthlyAmount, 15.99);
  assert.equal(overview.recurringPayments[0].nextExpectedDate, "2026-09-05");
  assert.equal(overview.recurringPayments[0].chargesLast12Months, 4);
  assert.equal(overview.recurringPayments[0].spentLast12Months, 63.96);
  assert.equal(overview.monthlyRecurringTotal, 15.99);
});

test("does not label ordinary repeat purchases or old canceled charges as subscriptions", () => {
  const groceryDates = ["2026-07-18", "2026-07-25", "2026-08-01", "2026-08-08"];
  const canceledDates = ["2025-11-10", "2025-12-10", "2026-01-10"];
  const records = [
    ...groceryDates.map((date, index) => ({
      entityType: "TRANSACTION",
      ...normalizeTransaction({
        transaction_id: `grocery-${index}`,
        account_id: "checking-1",
        date,
        name: "Neighborhood Market",
        amount: 42,
        pending: false,
        iso_currency_code: "USD",
        personal_finance_category: { primary: "FOOD_AND_DRINK" }
      })
    })),
    ...canceledDates.map((date, index) => ({
      entityType: "TRANSACTION",
      ...normalizeTransaction({
        transaction_id: `canceled-${index}`,
        account_id: "credit-1",
        date,
        name: "Old Video Service",
        amount: 12,
        pending: false,
        iso_currency_code: "USD",
        personal_finance_category: { primary: "ENTERTAINMENT" }
      })
    }))
  ];

  const overview = buildOverview(records, new Date("2026-08-11T12:00:00Z"));

  assert.deepEqual(overview.recurringPayments, []);
  assert.equal(overview.monthlyRecurringTotal, 0);
});

test("builds a current-month spending breakdown without pending charges", () => {
  const records = [
    { entityType: "TRANSACTION", ...normalizeTransaction({
      transaction_id: "rent", account_id: "checking", date: "2026-08-01", name: "Rent",
      amount: 1200, pending: false, iso_currency_code: "USD",
      personal_finance_category: { primary: "RENT_AND_UTILITIES" }
    }) },
    { entityType: "TRANSACTION", ...normalizeTransaction({
      transaction_id: "dinner", account_id: "credit", date: "2026-08-03", name: "Dinner",
      amount: 100, pending: false, iso_currency_code: "USD",
      personal_finance_category: { primary: "FOOD_AND_DRINK" }
    }) },
    { entityType: "TRANSACTION", ...normalizeTransaction({
      transaction_id: "pending", account_id: "credit", date: "2026-08-04", name: "Pending Dinner",
      amount: 50, pending: true, iso_currency_code: "USD",
      personal_finance_category: { primary: "FOOD_AND_DRINK" }
    }) }
  ];

  const overview = buildOverview(records, new Date("2026-08-11T12:00:00Z"));

  assert.equal(overview.monthlyOutflow, 1300);
  assert.deepEqual(overview.spendingByCategory.map(category => category.name), [
    "Rent And Utilities",
    "Food And Drink"
  ]);
  assert.equal(overview.spendingByCategory[0].amount, 1200);
  assert.equal(overview.spendingByCategory[0].share, 0.9231);
});

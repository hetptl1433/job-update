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

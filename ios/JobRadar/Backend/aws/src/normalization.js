import { createHash } from "node:crypto";

const ACCOUNT_TYPES = Object.freeze({
  depository: null,
  credit: "creditCard",
  investment: "investment",
  brokerage: "investment",
  loan: "loan"
});

function accountKind(account) {
  if (account.type === "depository") {
    if (account.subtype === "checking") return "checking";
    if (account.subtype === "savings" || account.subtype === "money market") return "savings";
    return "other";
  }
  return ACCOUNT_TYPES[account.type] ?? "other";
}

function currency(value) {
  return value?.iso_currency_code || value?.unofficial_currency_code || "USD";
}

export function normalizeAccount(account, item) {
  return {
    id: account.account_id,
    itemID: item.itemID,
    institutionName: item.institutionName,
    name: account.name || "Account",
    officialName: account.official_name || null,
    mask: account.mask || null,
    kind: accountKind(account),
    subtype: account.subtype || null,
    currentBalance: Number(account.balances?.current ?? 0),
    availableBalance: account.balances?.available == null ? null : Number(account.balances.available),
    currencyCode: currency(account.balances),
    liability: null
  };
}

function providerCategoryPrimary(transaction) {
  return String(
    transaction.providerCategoryPrimary
      ?? transaction.personal_finance_category?.primary
      ?? ""
  ).toUpperCase();
}

function providerCategoryDetailed(transaction) {
  return String(
    transaction.providerCategoryDetailed
      ?? transaction.personal_finance_category?.detailed
      ?? ""
  ).toUpperCase();
}

function legacyCategory(transaction) {
  if (Array.isArray(transaction.category)) return transaction.category[0] || null;
  return transaction.category || null;
}

function titleCaseProviderCategory(value) {
  return value.toLowerCase().split("_").map(word =>
    word[0]?.toUpperCase() + word.slice(1)
  ).join(" ");
}

function normalizedTransactionText(transaction) {
  return [
    transaction.name,
    transaction.merchantName,
    transaction.merchant_name,
    legacyCategory(transaction)
  ]
    .filter(Boolean)
    .join(" ")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function normalizedMerchantText(transaction) {
  return [transaction.name, transaction.merchantName, transaction.merchant_name]
    .filter(Boolean)
    .join(" ")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function merchantProfile(transaction) {
  const text = normalizedMerchantText(transaction);
  if (/\b(openai|chatgpt)\b/.test(text)) {
    return { key: "openai", name: "OpenAI", category: "Subscriptions", strength: "strong" };
  }
  if (/\b(playstation|play station|psn|sony interactive entertainment)\b/.test(text)) {
    const strength = /\b(playstation plus|play station plus|ps plus|psplus|subscription|membership)\b/.test(text)
      ? "strong"
      : "possible";
    return { key: "playstation", name: "PlayStation", category: "Entertainment", strength };
  }

  const foodMerchant = /\b(door ?dash|grubhub|uber ?eats|instacart|starbucks|dunkin|mcdonalds?|chipotle|chick fil a|taco bell|panera|subway|wendys?|burger king|dominos?|pizza hut|whole foods|trader joes?|kroger|publix|aldi|wegmans)\b/;
  const foodDescription = /\b(restaurant|coffee shop|coffee house|cafe|cafeteria|bakery|pizzeria|sushi|steakhouse|bar and grill|grocery|supermarket)\b/;
  if (foodMerchant.test(text) || foodDescription.test(text)) {
    return { key: null, name: null, category: "Food And Drink", strength: null };
  }
  return null;
}

function explicitSubscriptionHint(transaction) {
  const profile = merchantProfile(transaction);
  if (profile?.strength) return profile.strength;
  if (/subscription/i.test(String(legacyCategory(transaction) ?? ""))) return "strong";
  const text = normalizedMerchantText(transaction);
  return /\b(subscription|membership|monthly plan|annual plan|recurring charge)\b/.test(text)
    ? "strong"
    : null;
}

function isCreditCardPayment(transaction) {
  const detailed = providerCategoryDetailed(transaction);
  if (detailed === "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT") return true;

  const category = String(legacyCategory(transaction) ?? "").toLowerCase();
  if (/credit.?card.*(payment|bill)|card.*payment/.test(category)) return true;

  // The detailed Plaid category is authoritative. These conservative text
  // fallbacks cover older stored records and institutions whose descriptions
  // arrive as "AMEX EPAYMENT" or "CARDMEMBER AUTOPAY".
  const text = normalizedTransactionText(transaction);
  const hasCardSignal = /\b(amex|american express|discover|capital one|cardmember|credit card|cc)\b/.test(text);
  const hasPaymentSignal = /\b(payment|pymt|pmt|epay|epayment|autopay|paymt|thank you)\b/.test(text);
  return hasCardSignal && hasPaymentSignal;
}

function transactionNature(transaction) {
  if (isCreditCardPayment(transaction)) return "creditCardPayment";

  const primary = providerCategoryPrimary(transaction);
  if (primary === "TRANSFER_IN" || primary === "TRANSFER_OUT") return "accountTransfer";
  if (primary === "LOAN_PAYMENTS") return "loanPayment";
  if (primary === "INCOME") return "income";

  const category = String(legacyCategory(transaction) ?? "").toLowerCase();
  if (/\btransfer\b/.test(category)) return "accountTransfer";
  if (/\bloan payments?\b/.test(category)) return "loanPayment";
  if (/\bincome\b/.test(category)) return "income";

  const direction = transaction.direction
    ?? (Number(transaction.amount ?? 0) < 0 ? "inflow" : "outflow");
  if (direction === "outflow") return "purchase";
  if (direction === "inflow") return "refund";
  return "other";
}

function categoryName(transaction, nature = transactionNature(transaction)) {
  if (nature === "creditCardPayment") return "Credit Card Payment";
  if (nature === "accountTransfer") return "Transfer";
  if (nature === "loanPayment") return "Loan Payment";

  const primary = providerCategoryPrimary(transaction);
  const fallback = legacyCategory(transaction);
  const profile = merchantProfile(transaction);
  if (profile?.category) return profile.category;
  if (primary === "GENERAL_MERCHANDISE"
      || /\b(general )?merchandise\b/i.test(fallback ?? "")
      || /^shops?$/i.test(fallback ?? "")) {
    return "Shopping";
  }
  if (primary) return titleCaseProviderCategory(primary);
  return fallback;
}

export function normalizeTransaction(transaction, fallbackCurrency = "USD") {
  const rawAmount = Number(transaction.amount ?? 0);
  const direction = rawAmount < 0 ? "inflow" : "outflow";
  const nature = transactionNature({ ...transaction, direction });
  const profile = merchantProfile(transaction);
  return {
    id: transaction.transaction_id,
    accountID: transaction.account_id,
    // Plaid's `date` is the posted/settlement date used for every reporting
    // period. Authorization timing is useful context, but must never move a
    // posted transaction into a different income month.
    date: transaction.date,
    authorizedDate: transaction.authorized_date || null,
    name: transaction.name || "Transaction",
    merchantName: transaction.merchant_name || null,
    category: categoryName(transaction, nature),
    categorySource: profile?.category ? "merchantRule" : "provider",
    providerCategoryPrimary: transaction.personal_finance_category?.primary || null,
    providerCategoryDetailed: transaction.personal_finance_category?.detailed || null,
    providerCategoryConfidence: transaction.personal_finance_category?.confidence_level || null,
    paymentChannel: transaction.payment_channel || null,
    transactionCode: transaction.transaction_code || null,
    pendingTransactionID: transaction.pending_transaction_id || null,
    amount: Math.abs(rawAmount),
    direction,
    nature,
    pending: Boolean(transaction.pending),
    currencyCode: currency(transaction) || fallbackCurrency
  };
}

function publicAccount(record) {
  return {
    id: record.id,
    itemID: record.itemID,
    institutionName: record.institutionName,
    name: record.name,
    officialName: record.officialName ?? null,
    mask: record.mask ?? null,
    kind: record.kind,
    subtype: record.subtype ?? null,
    currentBalance: record.currentBalance,
    availableBalance: record.availableBalance ?? null,
    currencyCode: record.currencyCode,
    liability: record.liability ?? null
  };
}

function publicTransaction(record) {
  const nature = transactionNature(record);
  const profile = merchantProfile(record);
  return {
    id: record.id,
    accountID: record.accountID,
    date: record.date,
    authorizedDate: record.authorizedDate ?? null,
    name: record.name,
    merchantName: record.merchantName ?? null,
    category: categoryName(record, nature),
    categorySource: record.categorySource ?? (profile?.category ? "merchantRule" : "provider"),
    providerCategoryConfidence: record.providerCategoryConfidence ?? null,
    amount: record.amount,
    direction: record.direction,
    nature,
    pending: record.pending,
    currencyCode: record.currencyCode
  };
}

const DAY_MILLISECONDS = 86_400_000;
const RECURRING_CADENCES = Object.freeze([
  { cadence: "weekly", days: 7, tolerance: 2, minimumOccurrences: 3, monthlyFactor: 52 / 12 },
  { cadence: "biweekly", days: 14, tolerance: 3, minimumOccurrences: 3, monthlyFactor: 26 / 12 },
  { cadence: "monthly", days: 30.4375, tolerance: 7, minimumOccurrences: 3, monthlyFactor: 1 },
  { cadence: "quarterly", days: 91.3125, tolerance: 14, minimumOccurrences: 3, monthlyFactor: 1 / 3 },
  { cadence: "annual", days: 365.25, tolerance: 40, minimumOccurrences: 2, monthlyFactor: 1 / 12 }
]);
const NON_RECURRING_CATEGORY = /food|general merchandise|shopping|transportation|travel|medical|transfer|income/i;

function median(values) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function roundMoney(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function recurringDescriptor(transaction) {
  const profile = merchantProfile(transaction);
  if (profile?.key) return profile.key;
  const raw = transaction.merchantName || transaction.name || "";
  return raw
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/^(?:sq \*|tst\*|paypal \*|google \*|apple\.com\/bill\s*)/, "")
    .replace(/\b(?:purchase|payment|debit|recurring|subscription)\b/g, " ")
    .replace(/\b\d{4,}\b/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function utcDay(dateString) {
  const milliseconds = Date.parse(`${dateString}T00:00:00Z`);
  return Number.isFinite(milliseconds) ? milliseconds : null;
}

function addUTCDays(dateString, days) {
  const start = utcDay(dateString);
  if (start == null) return null;
  return new Date(start + Math.round(days) * DAY_MILLISECONDS).toISOString().slice(0, 10);
}

function detectCadence(transactions, allowTwoOccurrences = false) {
  const dated = transactions
    .map(transaction => ({ transaction, day: utcDay(transaction.date) }))
    .filter(entry => entry.day != null)
    .sort((a, b) => a.day - b.day);
  if (dated.length < 2) return null;

  // Multiple same-day charges from one merchant are purchases, not evidence
  // of a recurring interval. Keep one representative per posting date.
  const uniqueDays = [];
  for (const entry of dated) {
    if (uniqueDays.at(-1)?.day === entry.day) continue;
    uniqueDays.push(entry);
  }
  if (uniqueDays.length < 2) return null;

  const intervals = uniqueDays.slice(1).map((entry, index) =>
    (entry.day - uniqueDays[index].day) / DAY_MILLISECONDS
  );
  let best = null;
  for (const cadence of RECURRING_CADENCES) {
    const minimumOccurrences = allowTwoOccurrences
      ? Math.min(cadence.minimumOccurrences, 2)
      : cadence.minimumOccurrences;
    if (uniqueDays.length < minimumOccurrences) continue;
    const matching = intervals.filter(interval => Math.abs(interval - cadence.days) <= cadence.tolerance);
    const requiredMatches = intervals.length === 1
      ? 1
      : cadence.cadence === "annual"
      ? 1
      : Math.max(2, Math.ceil(intervals.length * 0.65));
    if (matching.length < requiredMatches) continue;

    const averageError = matching.reduce(
      (total, interval) => total + Math.abs(interval - cadence.days) / cadence.tolerance,
      0
    ) / matching.length;
    const score = (matching.length / intervals.length) - averageError * 0.15;
    if (!best || score > best.score) {
      best = { ...cadence, score, intervalDays: median(matching), occurrences: uniqueDays.length };
    }
  }
  return best;
}

function recurringPayments(transactions, now) {
  const groups = new Map();
  for (const transaction of transactions) {
    if (transaction.pending
        || transaction.direction !== "outflow"
        || transaction.nature !== "purchase"
        || transaction.amount < 0.5) continue;
    const descriptor = recurringDescriptor(transaction);
    if (descriptor.length < 2) continue;
    const key = `${transaction.currencyCode}|${descriptor}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(transaction);
  }

  const today = now.toISOString().slice(0, 10);
  const todayDay = utcDay(today);
  const rollingYearStart = new Date(now.getTime() - (365 * DAY_MILLISECONDS)).toISOString().slice(0, 10);
  const results = [];
  for (const [key, group] of groups) {
    const hints = group.map(explicitSubscriptionHint).filter(Boolean);
    const hint = hints.includes("strong") ? "strong" : hints.includes("possible") ? "possible" : null;
    const cadence = detectCadence(group, hint === "strong");
    const amounts = group.map(transaction => transaction.amount);
    const typicalAmount = median(amounts);
    const fixedTolerance = Math.max(3, typicalAmount * 0.2);
    const consistentCount = amounts.filter(amount => Math.abs(amount - typicalAmount) <= fixedTolerance).length;
    const amountConsistency = consistentCount / amounts.length;
    const latest = [...group].sort((a, b) => b.date.localeCompare(a.date))[0];
    const category = latest.category ?? null;
    if (NON_RECURRING_CATEGORY.test(category ?? "")) continue;
    const latestDay = utcDay(latest.date);
    if (latestDay == null || todayDay == null) continue;
    const daysSinceLatest = (todayDay - latestDay) / DAY_MILLISECONDS;
    const chargesLast12Months = group.filter(transaction =>
      transaction.date >= rollingYearStart && transaction.date <= today
    );
    const profile = merchantProfile(latest);

    // Merchant knowledge makes a new OpenAI/PlayStation/membership charge
    // visible immediately, but it remains a review suggestion until posting
    // history proves a cadence. Suggested items do not enter monthly totals.
    if (!cadence) {
      if (!hint || daysSinceLatest > 400) continue;
      results.push({
        id: createHash("sha256").update(key, "utf8").digest("hex").slice(0, 24),
        name: profile?.name || latest.merchantName || latest.name,
        category,
        amount: roundMoney(typicalAmount),
        monthlyAmount: roundMoney(typicalAmount),
        currencyCode: latest.currencyCode,
        cadence: "irregular",
        lastChargeDate: latest.date,
        nextExpectedDate: null,
        occurrences: new Set(group.map(transaction => transaction.date)).size,
        chargesLast12Months: chargesLast12Months.length,
        spentLast12Months: roundMoney(chargesLast12Months.reduce(
          (total, transaction) => total + transaction.amount,
          0
        )),
        isVariable: amounts.some(amount => Math.abs(amount - typicalAmount) > Math.max(1, typicalAmount * 0.05)),
        confidence: hint === "strong" ? 0.72 : 0.55,
        status: "possible",
        detectionSource: "merchantKnowledge"
      });
      continue;
    }

    const variableCategory = /rent|utilit|telecommunication|insurance/i.test(category ?? "");
    if (amountConsistency < (variableCategory ? 0.5 : 0.75)) continue;
    if (daysSinceLatest > cadence.days * 1.8 + cadence.tolerance) continue;

    let nextExpectedDate = addUTCDays(latest.date, cadence.intervalDays || cadence.days);
    // A payment can post a few days late. Once its estimated date has passed,
    // roll the prediction forward one cadence instead of displaying a stale
    // date as a guaranteed overdue bill.
    for (let index = 0; nextExpectedDate && nextExpectedDate < today && index < 3; index += 1) {
      nextExpectedDate = addUTCDays(nextExpectedDate, cadence.intervalDays || cadence.days);
    }

    const monthlyAmount = roundMoney(typicalAmount * cadence.monthlyFactor);
    const confidence = Math.min(0.99, Math.max(0.5,
      cadence.score * 0.65 + amountConsistency * 0.25 + Math.min(group.length / 12, 1) * 0.1
    ));
    results.push({
      id: createHash("sha256").update(key, "utf8").digest("hex").slice(0, 24),
      name: profile?.name || latest.merchantName || latest.name,
      category,
      amount: roundMoney(typicalAmount),
      monthlyAmount,
      currencyCode: latest.currencyCode,
      cadence: cadence.cadence,
      lastChargeDate: latest.date,
      nextExpectedDate,
      occurrences: cadence.occurrences,
      chargesLast12Months: chargesLast12Months.length,
      spentLast12Months: roundMoney(chargesLast12Months.reduce(
        (total, transaction) => total + transaction.amount,
        0
      )),
      isVariable: amounts.some(amount => Math.abs(amount - typicalAmount) > Math.max(1, typicalAmount * 0.05)),
      confidence: Math.round(confidence * 100) / 100,
      status: "confirmed",
      detectionSource: hint ? "merchantAndHistory" : "history"
    });
  }

  return results.sort((a, b) =>
    (a.status === b.status ? 0 : a.status === "confirmed" ? -1 : 1)
      || (a.nextExpectedDate ?? "9999").localeCompare(b.nextExpectedDate ?? "9999")
      || a.name.localeCompare(b.name)
  );
}

function spendingByCategory(transactions, currentMonth, monthlyOutflow) {
  const totals = new Map();
  for (const transaction of transactions) {
    if (transaction.pending
        || transaction.direction !== "outflow"
        || transaction.nature !== "purchase"
        || !transaction.date.startsWith(currentMonth)) {
      continue;
    }
    const name = transaction.category || "Other";
    totals.set(name, (totals.get(name) ?? 0) + transaction.amount);
  }
  return [...totals.entries()]
    .map(([name, amount]) => ({
      id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "other",
      name,
      amount: roundMoney(amount),
      share: monthlyOutflow > 0 ? Math.round((amount / monthlyOutflow) * 10_000) / 10_000 : 0
    }))
    .sort((a, b) => b.amount - a.amount || a.name.localeCompare(b.name))
    .slice(0, 6);
}

export function buildOverview(records, now = new Date()) {
  const itemRecords = records.filter(record => record.entityType === "PLAID_ITEM");
  const accounts = records.filter(record => record.entityType === "ACCOUNT").map(publicAccount);
  const transactions = records
    .filter(record => record.entityType === "TRANSACTION")
    .map(publicTransaction)
    .sort((a, b) => b.date.localeCompare(a.date) || a.name.localeCompare(b.name));

  const currentMonth = now.toISOString().slice(0, 7);
  let monthlyInflow = 0;
  let monthlyOutflow = 0;
  for (const transaction of transactions) {
    if (transaction.pending || !transaction.date.startsWith(currentMonth)) continue;
    if (transaction.direction === "outflow" && transaction.nature === "purchase") {
      monthlyOutflow += transaction.amount;
    } else if (transaction.direction === "inflow"
        && transaction.nature !== "creditCardPayment"
        && transaction.nature !== "accountTransfer"
        && transaction.nature !== "loanPayment") {
      monthlyInflow += transaction.amount;
    }
  }

  const countByItem = new Map();
  for (const account of accounts) countByItem.set(account.itemID, (countByItem.get(account.itemID) ?? 0) + 1);

  const institutions = itemRecords.map(item => ({
    id: item.itemID,
    name: item.institutionName || "Financial institution",
    accountCount: countByItem.get(item.itemID) ?? 0,
    needsAttention: Boolean(item.needsAttention)
  })).sort((a, b) => a.name.localeCompare(b.name));

  const totalCash = accounts
    .filter(account => account.kind === "checking" || account.kind === "savings")
    .reduce((total, account) => total + account.currentBalance, 0);
  const totalCreditBalance = accounts
    .filter(account => account.kind === "creditCard")
    .reduce((total, account) => total + Math.max(account.currentBalance, 0), 0);
  const totalInvestments = accounts
    .filter(account => account.kind === "investment")
    .reduce((total, account) => total + account.currentBalance, 0);
  const recurring = recurringPayments(transactions, now);
  const categories = spendingByCategory(transactions, currentMonth, monthlyOutflow);

  const lastUpdatedAt = records
    .map(record => record.updatedAt)
    .filter(Boolean)
    .sort()
    .at(-1) ?? null;

  return {
    institutions,
    accounts: accounts.sort((a, b) => a.institutionName.localeCompare(b.institutionName) || a.name.localeCompare(b.name)),
    recentTransactions: transactions,
    monthlyInflow,
    monthlyOutflow,
    totalCash,
    totalCreditBalance,
    totalInvestments,
    recurringPayments: recurring,
    monthlyRecurringTotal: roundMoney(recurring
      .filter(payment => payment.status !== "possible")
      .reduce((total, payment) => total + payment.monthlyAmount, 0)),
    spendingByCategory: categories,
    currencyCode: accounts[0]?.currencyCode ?? "USD",
    lastUpdatedAt
  };
}

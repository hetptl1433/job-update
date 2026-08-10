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

function categoryName(transaction) {
  const category = transaction.personal_finance_category?.primary;
  if (category) {
    return category.toLowerCase().split("_").map(word => word[0]?.toUpperCase() + word.slice(1)).join(" ");
  }
  return transaction.category?.[0] || null;
}

export function normalizeTransaction(transaction, fallbackCurrency = "USD") {
  const rawAmount = Number(transaction.amount ?? 0);
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
    category: categoryName(transaction),
    providerCategoryPrimary: transaction.personal_finance_category?.primary || null,
    providerCategoryDetailed: transaction.personal_finance_category?.detailed || null,
    providerCategoryConfidence: transaction.personal_finance_category?.confidence_level || null,
    paymentChannel: transaction.payment_channel || null,
    transactionCode: transaction.transaction_code || null,
    pendingTransactionID: transaction.pending_transaction_id || null,
    amount: Math.abs(rawAmount),
    direction: rawAmount < 0 ? "inflow" : "outflow",
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
  return {
    id: record.id,
    accountID: record.accountID,
    date: record.date,
    authorizedDate: record.authorizedDate ?? null,
    name: record.name,
    merchantName: record.merchantName ?? null,
    category: record.category ?? null,
    amount: record.amount,
    direction: record.direction,
    pending: record.pending,
    currencyCode: record.currencyCode
  };
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
    if (transaction.direction === "inflow") monthlyInflow += transaction.amount;
    else monthlyOutflow += transaction.amount;
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

  const lastUpdatedAt = records
    .map(record => record.updatedAt)
    .filter(Boolean)
    .sort()
    .at(-1) ?? null;

  return {
    institutions,
    accounts: accounts.sort((a, b) => a.institutionName.localeCompare(b.institutionName) || a.name.localeCompare(b.name)),
    recentTransactions: transactions.slice(0, 50),
    monthlyInflow,
    monthlyOutflow,
    totalCash,
    totalCreditBalance,
    totalInvestments,
    currencyCode: accounts[0]?.currencyCode ?? "USD",
    lastUpdatedAt
  };
}

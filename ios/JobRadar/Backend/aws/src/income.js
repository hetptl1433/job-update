import { createHash } from "node:crypto";

export const INCOME_SOURCE_TYPES = Object.freeze([
  "salary",
  "hourly",
  "contract",
  "freelance",
  "consulting",
  "business",
  "bonus",
  "commission",
  "interest",
  "dividend",
  "other"
]);

export const INCOME_FREQUENCIES = Object.freeze([
  "weekly",
  "biweekly",
  "semimonthly",
  "monthly",
  "irregular",
  "oneTime"
]);

export const MINIMUM_AI_CLASSIFICATION_CONFIDENCE = 0.80;

const DAY_MILLISECONDS = 86_400_000;
const USER_CLASSIFICATIONS = new Set(["income", "notIncome"]);
const CLASSIFICATION_DECISION_SOURCES = new Set(["user", "ai"]);
const REGULAR_FREQUENCIES = new Set(["weekly", "biweekly", "semimonthly", "monthly"]);

function normalizedText(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/\b\d{6,}\b/g, " number ")
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function finitePositiveAmount(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0 ? amount : null;
}

function roundAmount(value) {
  if (!Number.isFinite(value)) return 0;
  return Math.round((value + Number.EPSILON) * 1_000_000) / 1_000_000;
}

function sumAmounts(values) {
  return roundAmount(values.reduce((total, value) => total + Number(value || 0), 0));
}

export function isValidDateOnly(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function dateMilliseconds(value) {
  if (!isValidDateOnly(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  return Date.UTC(year, month - 1, day);
}

function dateFromMilliseconds(value) {
  return new Date(value).toISOString().slice(0, 10);
}

function addDays(value, count) {
  return dateFromMilliseconds(dateMilliseconds(value) + (count * DAY_MILLISECONDS));
}

function dayDifference(first, second) {
  return Math.round((dateMilliseconds(second) - dateMilliseconds(first)) / DAY_MILLISECONDS);
}

function monthKey(value) {
  return value.slice(0, 7);
}

function shiftMonthKey(value, offset) {
  const [year, month] = value.split("-").map(Number);
  const shifted = new Date(Date.UTC(year, month - 1 + offset, 1));
  return shifted.toISOString().slice(0, 7);
}

function daysInMonth(month) {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number, 0)).getUTCDate();
}

function monthEnd(month) {
  return `${month}-${String(daysInMonth(month)).padStart(2, "0")}`;
}

function addMonthsClamped(value, count) {
  const [year, month, day] = value.split("-").map(Number);
  const first = new Date(Date.UTC(year, month - 1 + count, 1));
  const shiftedMonth = first.toISOString().slice(0, 7);
  return `${shiftedMonth}-${String(Math.min(day, daysInMonth(shiftedMonth))).padStart(2, "0")}`;
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
}

function average(values) {
  return values.length === 0 ? 0 : sumAmounts(values) / values.length;
}

function clusterCount(values, tolerance = 3) {
  const sorted = [...new Set(values)].sort((a, b) => a - b);
  const clusters = [];
  for (const value of sorted) {
    const cluster = clusters.find(candidate => Math.abs(candidate.at(-1) - value) <= tolerance);
    if (cluster) cluster.push(value);
    else clusters.push([value]);
  }
  return clusters.length;
}

function dayClusters(values, tolerance = 3) {
  const clusters = [];
  for (const value of [...new Set(values)].sort((a, b) => a - b)) {
    const cluster = clusters.at(-1);
    if (cluster && Math.abs(cluster.at(-1) - value) <= tolerance) cluster.push(value);
    else clusters.push([value]);
  }
  return clusters;
}

export function inferIncomeFrequency(dateValues) {
  const dates = [...new Set(dateValues.filter(isValidDateOnly))].sort();
  if (dates.length <= 1) return "oneTime";

  const gaps = [];
  for (let index = 1; index < dates.length; index += 1) {
    const gap = dayDifference(dates[index - 1], dates[index]);
    if (gap > 0) gaps.push(gap);
  }
  if (gaps.length === 0) return "oneTime";

  const matchingRatio = (minimum, maximum) =>
    gaps.filter(gap => gap >= minimum && gap <= maximum).length / gaps.length;

  if (matchingRatio(5, 9) >= 0.7) return "weekly";
  if (matchingRatio(12, 18) >= 0.7) {
    if (dates.length >= 3) {
      const days = dates.map(date => Number(date.slice(8, 10)));
      if (new Set(days).size <= 2) return "semimonthly";
      if (Math.max(...gaps) - Math.min(...gaps) <= 1) return "biweekly";
      if (dates.length >= 4 && clusterCount(days) <= 2) return "semimonthly";
    }
    return "biweekly";
  }
  if (matchingRatio(25, 35) >= 0.7) return "monthly";
  return "irregular";
}

export function annualPaymentCount(frequency) {
  switch (frequency) {
  case "weekly": return 52;
  case "biweekly": return 26;
  case "semimonthly": return 24;
  case "monthly": return 12;
  default: return null;
  }
}

export function normalizedIncomeDescriptor(transaction) {
  const identity = normalizedText(transaction.merchantName) || normalizedText(transaction.name);
  const category = normalizedText(
    transaction.providerCategoryDetailed || transaction.providerCategoryPrimary || transaction.category
  );
  const channel = normalizedText(transaction.paymentChannel);
  const account = normalizedText(transaction.accountID);
  return [account, identity, category, channel].join("|");
}

function transactionText(transaction) {
  return normalizedText([
    transaction.name,
    transaction.merchantName,
    transaction.category,
    transaction.providerCategoryPrimary,
    transaction.providerCategoryDetailed
  ].filter(Boolean).join(" "));
}

function hasProviderTransferSignal(transaction) {
  const primary = String(transaction.providerCategoryPrimary ?? "").toUpperCase();
  const detailed = String(transaction.providerCategoryDetailed ?? "").toUpperCase();
  return primary.startsWith("TRANSFER_") || detailed.startsWith("TRANSFER_");
}

function hasTransferSignal(transaction) {
  const text = transactionText(transaction);
  return hasProviderTransferSignal(transaction) ||
    /\b(transfer|xfer|internal transfer|account transfer)\b/.test(text);
}

function isPeerToPeer(transaction) {
  return /\b(venmo|zelle|cash app|cashapp|peer to peer|p2p|paypal transfer)\b/.test(transactionText(transaction));
}

function exclusionDecision(transaction) {
  const detailed = String(transaction.providerCategoryDetailed ?? "").toUpperCase();
  const text = transactionText(transaction);

  if (detailed.includes("CASH_ADVANCES_AND_LOANS") ||
      /\b(loan proceeds?|loan disbursement|loan funding|cash advance|borrowed funds?)\b/.test(text)) {
    return {
      reason: "loanProceeds",
      decisionSource: detailed.includes("CASH_ADVANCES_AND_LOANS") ? "provider" : "deterministicRule"
    };
  }
  if (/\b(reimburse|reimbursed|reimbursement|expense repayment|expense reimbursement)\b/.test(text)) {
    return { reason: "reimbursement", decisionSource: "deterministicRule" };
  }
  if (detailed.includes("REFUND") ||
      /\b(refund|returns?|returned|merchant credit|reversal|reversed)\b/.test(text)) {
    return {
      reason: "refundOrReversal",
      decisionSource: detailed.includes("REFUND") ? "provider" : "deterministicRule"
    };
  }
  return null;
}

function isStrongProviderIncome(transaction) {
  const primary = String(transaction.providerCategoryPrimary ?? "").toUpperCase();
  const detailed = String(transaction.providerCategoryDetailed ?? "").toUpperCase();
  const confidence = String(transaction.providerCategoryConfidence ?? "").toUpperCase();
  const strongDetails = new Set([
    "INCOME_WAGES",
    "INCOME_DIVIDENDS",
    "INCOME_INTEREST_EARNED",
    "INCOME_RETIREMENT_PENSION",
    "INCOME_UNEMPLOYMENT"
  ]);
  return primary === "INCOME" && strongDetails.has(detailed) && ["HIGH", "VERY_HIGH"].includes(confidence);
}

function isKeywordIncomeCandidate(transaction) {
  return /\b(payroll|paycheck|salary|wages?|direct deposit|employer payment|contract payment|consulting|freelance|commission|bonus|tips?|interest|dividend)\b/
    .test(transactionText(transaction));
}

function inferredSourceType(transaction, override) {
  if (INCOME_SOURCE_TYPES.includes(override)) return override;
  const text = transactionText(transaction);
  if (/\binterest\b/.test(text)) return "interest";
  if (/\bdividend\b/.test(text)) return "dividend";
  if (/\bbonus\b/.test(text)) return "bonus";
  if (/\bcommission\b/.test(text)) return "commission";
  if (/\bconsult(?:ing|ant)\b/.test(text)) return "consulting";
  if (/\bfreelance\b/.test(text)) return "freelance";
  if (/\bcontract(?:or)?\b/.test(text)) return "contract";
  if (/\bbusiness\b/.test(text)) return "business";
  if (/\bhourly\b/.test(text)) return "hourly";
  if (/\b(payroll|paycheck|salary|wages?|direct deposit)\b/.test(text) ||
      String(transaction.providerCategoryDetailed ?? "").toUpperCase() === "INCOME_WAGES") {
    return "salary";
  }
  return "other";
}

function sourceName(transaction, override) {
  const chosen = typeof override === "string" && override.trim() ? override.trim() :
    (typeof transaction.merchantName === "string" && transaction.merchantName.trim() ? transaction.merchantName.trim() :
      (typeof transaction.name === "string" && transaction.name.trim() ? transaction.name.trim() : "Income"));
  return chosen.slice(0, 120);
}

function storedDecisionSource(record) {
  if (!record) return null;
  if (record.decisionSource == null) return "user";
  return CLASSIFICATION_DECISION_SOURCES.has(record.decisionSource) ? record.decisionSource : null;
}

function validClassificationRecord(record) {
  const decisionSource = storedDecisionSource(record);
  if (!decisionSource) return false;
  if (decisionSource === "user") return true;
  return typeof record.confidence === "number" && Number.isFinite(record.confidence) &&
    record.confidence >= MINIMUM_AI_CLASSIFICATION_CONFIDENCE && record.confidence <= 1 &&
    typeof record.reason === "string" && record.reason.trim().length > 0 &&
    record.reason.trim().length <= 280 && !/[\u0000-\u001f\u007f]/.test(record.reason);
}

function compareClassificationRecords(first, second) {
  const firstPriority = storedDecisionSource(first) === "user" ? 1 : 0;
  const secondPriority = storedDecisionSource(second) === "user" ? 1 : 0;
  return secondPriority - firstPriority ||
    String(second.updatedAt ?? second.createdAt ?? "")
      .localeCompare(String(first.updatedAt ?? first.createdAt ?? "")) ||
    String(first.transactionID ?? "").localeCompare(String(second.transactionID ?? ""));
}

function preferredRecords(records, keyForRecord) {
  const result = new Map();
  for (const record of records) {
    const key = keyForRecord(record);
    if (!key) continue;
    const existing = result.get(key);
    if (!existing || compareClassificationRecords(record, existing) < 0) {
      result.set(key, record);
    }
  }
  return result;
}

function resultFromRule(transaction, rule, isDirect) {
  const decisionSource = storedDecisionSource(rule);
  const isUserDecision = decisionSource === "user";
  const confidence = isUserDecision ? (isDirect ? 1 : 0.98) : rule.confidence;
  const reason = isUserDecision
    ? (isDirect ? "userOverride" : "userDescriptorRule")
    : rule.reason.trim();
  const shared = {
    reason,
    confidence,
    userConfirmed: isUserDecision,
    decisionSource
  };
  if (rule.classification === "notIncome") {
    return { status: "excluded", ...shared };
  }
  return {
    status: "confirmed",
    ...shared,
    sourceName: sourceName(transaction, rule.sourceName),
    sourceType: inferredSourceType(transaction, rule.sourceType ?? rule.type)
  };
}

function preferredRule(directRule, inheritedRule) {
  if (storedDecisionSource(directRule) === "user") {
    return { rule: directRule, isDirect: true };
  }
  if (storedDecisionSource(inheritedRule) === "user") {
    return { rule: inheritedRule, isDirect: false };
  }
  if (directRule) return { rule: directRule, isDirect: true };
  if (inheritedRule) return { rule: inheritedRule, isDirect: false };
  return null;
}

function transferReconciliation(transactions) {
  const inflows = transactions.filter(transaction => transaction.direction === "inflow");
  const outflows = transactions.filter(transaction => transaction.direction === "outflow");
  const paired = new Set();
  const ambiguous = new Set();
  const candidatesByInflow = new Map();
  const inflowCountByOutflow = new Map();

  for (const inflow of inflows.sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))) {
    if (!hasTransferSignal(inflow) || !isValidDateOnly(inflow.date)) continue;
    const amount = finitePositiveAmount(inflow.amount);
    if (amount == null) continue;
    const candidates = outflows
      .filter(outflow => outflow.accountID !== inflow.accountID &&
        String(outflow.currencyCode || "USD").toUpperCase() === String(inflow.currencyCode || "USD").toUpperCase() &&
        finitePositiveAmount(outflow.amount) != null &&
        Math.abs(Number(outflow.amount) - amount) < 0.000001 &&
        isValidDateOnly(outflow.date) && Math.abs(dayDifference(outflow.date, inflow.date)) <= 3 &&
        hasTransferSignal(outflow))
      .sort((first, second) =>
        Math.abs(dayDifference(first.date, inflow.date)) - Math.abs(dayDifference(second.date, inflow.date)) ||
        first.id.localeCompare(second.id));
    candidatesByInflow.set(inflow.id, candidates);
    for (const candidate of candidates) {
      inflowCountByOutflow.set(candidate.id, (inflowCountByOutflow.get(candidate.id) ?? 0) + 1);
    }
  }

  for (const [inflowID, candidates] of candidatesByInflow) {
    if (candidates.length === 1 && inflowCountByOutflow.get(candidates[0].id) === 1) {
      paired.add(inflowID);
    } else if (candidates.length > 0) {
      ambiguous.add(inflowID);
    }
  }
  return { paired, ambiguous };
}

function publicIncomeTransaction(transaction, classification) {
  return {
    id: transaction.id,
    accountID: transaction.accountID,
    date: transaction.date,
    authorizedDate: transaction.authorizedDate ?? null,
    name: transaction.name || "Transaction",
    merchantName: transaction.merchantName ?? null,
    category: transaction.category ?? null,
    amount: roundAmount(Number(transaction.amount)),
    direction: "inflow",
    pending: Boolean(transaction.pending),
    currencyCode: String(transaction.currencyCode || "USD").toUpperCase(),
    sourceName: classification.sourceName,
    sourceType: classification.sourceType,
    confidence: classification.confidence,
    classificationReason: classification.reason,
    userConfirmed: classification.userConfirmed,
    decisionSource: classification.decisionSource ?? null,
    classification: classification.status === "confirmed" ? "income" :
      (classification.status === "excluded" ? "notIncome" : "needsReview"),
    basis: "observedNetDeposit"
  };
}

export function classifyIncomeTransactions(records, options = {}) {
  const asOfDate = options.asOfDate;
  const transactions = records.filter(record => record.entityType === "TRANSACTION" &&
    typeof record.id === "string" && typeof record.accountID === "string" &&
    isValidDateOnly(record.date) && (!asOfDate || record.date <= asOfDate) &&
    finitePositiveAmount(record.amount) != null &&
    (record.direction === "inflow" || record.direction === "outflow"));
  const classificationRecords = records.filter(record => record.entityType === "INCOME_CLASSIFICATION" &&
    typeof record.transactionID === "string" && USER_CLASSIFICATIONS.has(record.classification) &&
    validClassificationRecord(record));
  const directRules = preferredRecords(classificationRecords, record => record.transactionID);
  const transactionsByID = new Map(transactions.map(transaction => [transaction.id, transaction]));
  const descriptorRules = new Map();
  for (const record of classificationRecords) {
    if (!record.descriptor) continue;
    const sourceDate = record.transactionDate ?? transactionsByID.get(record.transactionID)?.date;
    if (!isValidDateOnly(sourceDate)) continue;
    const rules = descriptorRules.get(record.descriptor) ?? [];
    rules.push({ ...record, transactionDate: sourceDate });
    descriptorRules.set(record.descriptor, rules);
  }
  for (const rules of descriptorRules.values()) {
    rules.sort(compareClassificationRecords);
  }
  const reconciledTransfers = transferReconciliation(transactions);
  const classified = [];

  for (const transaction of transactions) {
    if (transaction.direction !== "inflow") continue;

    const descriptor = normalizedIncomeDescriptor(transaction);
    const directRule = directRules.get(transaction.id) ??
      (transaction.pendingTransactionID ? directRules.get(transaction.pendingTransactionID) : null);
    const inheritedRule = descriptorRules.get(descriptor)?.find(rule => rule.transactionDate <= transaction.date);
    const chosenRule = preferredRule(directRule, inheritedRule);
    const directUserRule = chosenRule?.isDirect && storedDecisionSource(chosenRule.rule) === "user"
      ? chosenRule.rule
      : null;
    const automaticRule = directUserRule ? null : chosenRule;
    let result;

    if (directUserRule) {
      result = resultFromRule(transaction, directUserRule, true);
    } else if (reconciledTransfers.paired.has(transaction.id)) {
      result = {
        status: "excluded",
        reason: "ownAccountTransfer",
        confidence: 1,
        userConfirmed: false,
        decisionSource: "deterministicRule"
      };
    } else {
      const excluded = exclusionDecision(transaction);
      if (excluded) {
        result = {
          status: "excluded",
          reason: excluded.reason,
          confidence: 0.99,
          userConfirmed: false,
          decisionSource: excluded.decisionSource
        };
      } else if (reconciledTransfers.ambiguous.has(transaction.id)) {
        result = {
          status: "needsReview",
          reason: "ambiguousTransfer",
          confidence: 0.2,
          userConfirmed: false,
          decisionSource: "deterministicRule",
          sourceName: sourceName(transaction),
          sourceType: inferredSourceType(transaction)
        };
      } else if (isPeerToPeer(transaction)) {
        if (automaticRule) {
          result = resultFromRule(transaction, automaticRule.rule, automaticRule.isDirect);
        } else {
          result = {
            status: "needsReview",
            reason: "peerToPeer",
            confidence: 0.35,
            userConfirmed: false,
            decisionSource: "deterministicRule",
            sourceName: sourceName(transaction),
            sourceType: inferredSourceType(transaction)
          };
        }
      } else if (hasTransferSignal(transaction)) {
        if (automaticRule) {
          result = resultFromRule(transaction, automaticRule.rule, automaticRule.isDirect);
        } else {
          result = {
            status: "excluded",
            reason: "transferCategory",
            confidence: 0.98,
            userConfirmed: false,
            decisionSource: hasProviderTransferSignal(transaction) ? "provider" : "deterministicRule"
          };
        }
      } else {
        if (automaticRule) {
          result = resultFromRule(transaction, automaticRule.rule, automaticRule.isDirect);
        } else if (isStrongProviderIncome(transaction)) {
          result = {
            status: "confirmed",
            reason: "providerIncomeCategory",
            confidence: 0.9,
            userConfirmed: false,
            decisionSource: "provider",
            sourceName: sourceName(transaction),
            sourceType: inferredSourceType(transaction)
          };
        } else {
          const keywordCandidate = isKeywordIncomeCandidate(transaction);
          result = {
            status: "needsReview",
            reason: keywordCandidate ? "incomeKeyword" : "unrecognizedInflow",
            confidence: keywordCandidate ? 0.55 : 0.25,
            userConfirmed: false,
            decisionSource: "deterministicRule",
            sourceName: sourceName(transaction),
            sourceType: inferredSourceType(transaction)
          };
        }
      }
    }

    classified.push({
      transaction,
      descriptor,
      ...result,
      publicTransaction: publicIncomeTransaction(transaction, result)
    });
  }
  return classified;
}

function nextSemimonthlyDate(lastDate, dates) {
  const dayValues = dates.map(date => Number(date.slice(8, 10)));
  const clusters = dayClusters(dayValues);
  const early = Math.round(median(clusters[0] ?? [1]));
  const late = Math.round(median(clusters[1] ?? [Math.min(early + 15, 28)]));
  const currentDay = Number(lastDate.slice(8, 10));
  const currentMonth = monthKey(lastDate);
  if (Math.abs(currentDay - early) <= Math.abs(currentDay - late)) {
    return `${currentMonth}-${String(Math.min(late, daysInMonth(currentMonth))).padStart(2, "0")}`;
  }
  const nextMonth = shiftMonthKey(currentMonth, 1);
  return `${nextMonth}-${String(Math.min(early, daysInMonth(nextMonth))).padStart(2, "0")}`;
}

function nextRegularDate(lastDate, frequency, dates) {
  switch (frequency) {
  case "weekly": return addDays(lastDate, 7);
  case "biweekly": return addDays(lastDate, 14);
  case "semimonthly": return nextSemimonthlyDate(lastDate, dates);
  case "monthly": {
    const nextMonth = shiftMonthKey(monthKey(lastDate), 1);
    const preferredDay = Math.round(median(dates.map(date => Number(date.slice(8, 10)))) ?? Number(lastDate.slice(8, 10)));
    return `${nextMonth}-${String(Math.min(preferredDay, daysInMonth(nextMonth))).padStart(2, "0")}`;
  }
  default: return null;
  }
}

function advanceExpectedDate(lastDate, frequency, dates, afterDate) {
  let next = nextRegularDate(lastDate, frequency, dates);
  let guard = 0;
  while (next && next <= afterDate && guard < 80) {
    next = nextRegularDate(next, frequency, dates);
    guard += 1;
  }
  return guard >= 80 ? null : next;
}

function expectedInterval(frequency) {
  switch (frequency) {
  case "weekly": return 7;
  case "biweekly": return 14;
  case "semimonthly": return 16;
  case "monthly": return 31;
  default: return null;
  }
}

function isActiveSource(lastPaymentDate, frequency, asOfDate) {
  const interval = expectedInterval(frequency);
  if (!lastPaymentDate || !interval || lastPaymentDate > asOfDate) return false;
  return dayDifference(lastPaymentDate, asOfDate) <= Math.max(interval * 3, 35);
}

function sourceIdentifier(currencyCode, key) {
  return `income_${createHash("sha256").update(`${currencyCode}|${key}`).digest("hex").slice(0, 24)}`;
}

function buildSources(classified, asOfDate, thisMonth) {
  const groups = new Map();
  for (const entry of classified.filter(candidate => candidate.status === "confirmed")) {
    const transaction = entry.transaction;
    const name = entry.sourceName;
    const type = entry.sourceType;
    const key = [transaction.accountID, normalizedText(name), type].join("|");
    const group = groups.get(key) ?? { key, name, type, accountID: transaction.accountID, entries: [] };
    group.entries.push(entry);
    groups.set(key, group);
  }

  return [...groups.values()].map(group => {
    const posted = group.entries.filter(entry => !entry.transaction.pending).sort((a, b) =>
      a.transaction.date.localeCompare(b.transaction.date) || a.transaction.id.localeCompare(b.transaction.id));
    const pending = group.entries.filter(entry => entry.transaction.pending).sort((a, b) =>
      a.transaction.date.localeCompare(b.transaction.date) || a.transaction.id.localeCompare(b.transaction.id));
    const dates = posted.map(entry => entry.transaction.date);
    const amounts = posted.map(entry => Number(entry.transaction.amount));
    const frequency = inferIncomeFrequency(dates);
    const paymentAverage = roundAmount(average(amounts));
    const annualCount = annualPaymentCount(frequency);
    const firstDate = dates[0] ?? null;
    const lastPaymentDate = dates.at(-1) ?? null;
    const active = isActiveSource(lastPaymentDate, frequency, asOfDate);
    const latestKnownDate = [lastPaymentDate, pending.at(-1)?.transaction.date]
      .filter(Boolean).sort().at(-1) ?? null;
    const nextExpectedPaymentDate = active && latestKnownDate ?
      advanceExpectedDate(latestKnownDate, frequency, dates, asOfDate) : null;
    const monthSpan = firstDate && lastPaymentDate ?
      ((Number(lastPaymentDate.slice(0, 4)) - Number(firstDate.slice(0, 4))) * 12 +
        Number(lastPaymentDate.slice(5, 7)) - Number(firstDate.slice(5, 7)) + 1) : 1;
    const averageMonthly = annualCount ? paymentAverage * annualCount / 12 :
      (frequency === "irregular" ? sumAmounts(amounts) / Math.max(monthSpan, 1) : paymentAverage);
    const confidence = roundAmount(average(group.entries.map(entry => entry.confidence)));
    const currencyCode = String(group.entries[0].transaction.currencyCode || "USD").toUpperCase();
    const decisionSources = new Set(group.entries.map(entry => entry.decisionSource).filter(Boolean));
    const decisionSource = ["user", "ai", "provider", "deterministicRule"]
      .find(source => decisionSources.has(source)) ?? null;

    return {
      id: sourceIdentifier(currencyCode, group.key),
      name: group.name,
      type: group.type,
      accountID: group.accountID,
      frequency,
      averagePayment: paymentAverage,
      averageMonthly: roundAmount(averageMonthly),
      lastPaymentDate,
      nextExpectedPaymentDate,
      active,
      confidence,
      userConfirmed: group.entries.some(entry => entry.userConfirmed),
      decisionSource,
      thisMonth: sumAmounts(posted.filter(entry => monthKey(entry.transaction.date) === thisMonth)
        .map(entry => entry.transaction.amount)),
      yearToDate: sumAmounts(posted.filter(entry => entry.transaction.date.startsWith(`${asOfDate.slice(0, 4)}-`))
        .map(entry => entry.transaction.amount)),
      transactionCount: posted.length,
      basis: "observedNetDeposit",
      _dates: dates,
      _pending: pending,
      _annualCount: annualCount,
      _entries: group.entries
    };
  }).sort((first, second) => second.yearToDate - first.yearToDate || first.name.localeCompare(second.name));
}

function monthsBetweenInclusive(startMonth, endMonth) {
  const [startYear, startNumber] = startMonth.split("-").map(Number);
  const [endYear, endNumber] = endMonth.split("-").map(Number);
  return Math.max(0, ((endYear - startYear) * 12) + endNumber - startNumber + 1);
}

function buildCoverage(currencyTransactions, asOfDate) {
  const dates = currencyTransactions.map(transaction => transaction.date).filter(date => isValidDateOnly(date) && date <= asOfDate).sort();
  const startDate = dates[0] ?? null;
  if (!startDate) return { startDate: null, endDate: asOfDate, completeMonths: 0 };

  const firstCompleteMonth = startDate.endsWith("-01") ? monthKey(startDate) : shiftMonthKey(monthKey(startDate), 1);
  const currentComplete = asOfDate === monthEnd(monthKey(asOfDate));
  const lastCompleteMonth = currentComplete ? monthKey(asOfDate) : shiftMonthKey(monthKey(asOfDate), -1);
  return {
    startDate,
    endDate: asOfDate,
    completeMonths: firstCompleteMonth <= lastCompleteMonth ? monthsBetweenInclusive(firstCompleteMonth, lastCompleteMonth) : 0
  };
}

function bucketForMonth(classified, month) {
  const entries = classified.filter(entry => monthKey(entry.transaction.date) === month);
  return {
    confirmed: sumAmounts(entries.filter(entry => entry.status === "confirmed" && !entry.transaction.pending)
      .map(entry => entry.transaction.amount)),
    pending: sumAmounts(entries.filter(entry => entry.status === "confirmed" && entry.transaction.pending)
      .map(entry => entry.transaction.amount)),
    needsReview: sumAmounts(entries.filter(entry => entry.status === "needsReview")
      .map(entry => entry.transaction.amount))
  };
}

function strippedSource(source) {
  return Object.fromEntries(Object.entries(source).filter(([key]) => !key.startsWith("_")));
}

function expectedDatesThrough(source, asOfDate, endDate) {
  const result = [];
  if (!source.active || !source.nextExpectedPaymentDate || !source._annualCount) return result;
  let date = source.nextExpectedPaymentDate;
  let guard = 0;
  while (date <= endDate && guard < 60) {
    if (date > asOfDate) result.push(date);
    date = nextRegularDate(date, source.frequency, source._dates);
    guard += 1;
  }
  return result;
}

function buildCurrencySummary(currencyCode, currencyRecords, classified, asOfDate) {
  const thisMonthKey = monthKey(asOfDate);
  const lastMonthKey = shiftMonthKey(thisMonthKey, -1);
  const thisMonth = bucketForMonth(classified, thisMonthKey);
  const lastMonth = bucketForMonth(classified, lastMonthKey);
  const year = asOfDate.slice(0, 4);
  const yearToDate = sumAmounts(classified.filter(entry => entry.status === "confirmed" && !entry.transaction.pending &&
    entry.transaction.date.startsWith(`${year}-`)).map(entry => entry.transaction.amount));
  const coverage = buildCoverage(currencyRecords, asOfDate);
  const observedStartMonth = coverage.startDate && coverage.startDate.slice(0, 4) === year ? monthKey(coverage.startDate) : `${year}-01`;
  const observedMonthCount = coverage.startDate ? Math.max(1, monthsBetweenInclusive(observedStartMonth, thisMonthKey)) : 1;
  const sources = buildSources(classified, asOfDate, thisMonthKey);
  // At least three posted observations are required before two intervals are
  // treated as a recurring pattern suitable for forward-looking estimates.
  const supportedSources = sources.filter(source => {
    const minimumObservations = source.frequency === "biweekly" || source.frequency === "semimonthly" ? 4 : 3;
    return source.active && source._annualCount && source.transactionCount >= minimumObservations;
  });
  const estimatedAnnual = supportedSources.length > 0 ? sumAmounts(supportedSources.map(source =>
    source.averagePayment * source._annualCount)) : null;
  const confirmedPendingYTD = sumAmounts(classified.filter(entry => entry.status === "confirmed" && entry.transaction.pending &&
    entry.transaction.date.startsWith(`${year}-`)).map(entry => entry.transaction.amount));
  const expectedThroughMonth = supportedSources.flatMap(source => expectedDatesThrough(source, asOfDate, monthEnd(thisMonthKey))
    .map(() => source.averagePayment));
  const expectedThroughYear = supportedSources.flatMap(source => expectedDatesThrough(source, asOfDate, `${year}-12-31`)
    .map(() => source.averagePayment));
  const history = [];
  for (let offset = -11; offset <= 0; offset += 1) {
    const month = shiftMonthKey(thisMonthKey, offset);
    history.push({ month, ...bucketForMonth(classified, month) });
  }
  const expectedPaychecks = supportedSources
    .filter(source => source.nextExpectedPaymentDate)
    .map(source => ({
      sourceID: source.id,
      sourceName: source.name,
      date: source.nextExpectedPaymentDate,
      estimatedAmount: source.averagePayment,
      confidence: source.confidence
    }))
    .sort((first, second) => first.date.localeCompare(second.date) || first.sourceName.localeCompare(second.sourceName));

  return {
    currencyCode,
    basis: "observedNetDeposit",
    thisMonth,
    lastMonth,
    changeAmount: roundAmount(thisMonth.confirmed - lastMonth.confirmed),
    changePercent: lastMonth.confirmed === 0 ? null :
      roundAmount(((thisMonth.confirmed - lastMonth.confirmed) / lastMonth.confirmed) * 100),
    yearToDate,
    averageMonthly: roundAmount(yearToDate / observedMonthCount),
    estimatedAnnual,
    sources: sources.map(strippedSource),
    history,
    confirmedTransactions: classified.filter(entry => entry.status === "confirmed")
      .map(entry => entry.publicTransaction)
      .sort((first, second) => second.date.localeCompare(first.date) || first.name.localeCompare(second.name)),
    needsReviewTransactions: classified.filter(entry => entry.status === "needsReview")
      .map(entry => entry.publicTransaction)
      .sort((first, second) => second.date.localeCompare(first.date) || first.name.localeCompare(second.name)),
    excludedTransactions: classified.filter(entry => entry.status === "excluded")
      .map(entry => entry.publicTransaction)
      .sort((first, second) => second.date.localeCompare(first.date) || first.name.localeCompare(second.name)),
    projectedMonthEnd: supportedSources.length === 0 ? null :
      roundAmount(thisMonth.confirmed + thisMonth.pending + sumAmounts(expectedThroughMonth)),
    projectedYearEnd: supportedSources.length === 0 ? null :
      roundAmount(yearToDate + confirmedPendingYTD + sumAmounts(expectedThroughYear)),
    expectedPaychecks,
    coverage
  };
}

export function buildIncomeOverview(records, options) {
  if (!options || !isValidDateOnly(options.asOfDate)) {
    throw new TypeError("buildIncomeOverview requires a valid asOfDate.");
  }
  const asOfDate = options.asOfDate;
  const validTransactions = records.filter(record => record.entityType === "TRANSACTION" &&
    isValidDateOnly(record.date) && record.date <= asOfDate && finitePositiveAmount(record.amount) != null &&
    (record.direction === "inflow" || record.direction === "outflow"));
  const allClassified = classifyIncomeTransactions(records, { asOfDate });
  const currencyCodes = new Set();
  for (const record of records) {
    if ((record.entityType === "ACCOUNT" || record.entityType === "TRANSACTION") &&
        typeof record.currencyCode === "string" && record.currencyCode.trim()) {
      currencyCodes.add(record.currencyCode.trim().toUpperCase());
    }
  }

  const summaries = [...currencyCodes].sort().map(currencyCode => {
    const currencyTransactions = validTransactions.filter(transaction =>
      String(transaction.currencyCode || "USD").toUpperCase() === currencyCode);
    const classified = allClassified.filter(entry =>
      String(entry.transaction.currencyCode || "USD").toUpperCase() === currencyCode);
    return buildCurrencySummary(currencyCode, currencyTransactions, classified, asOfDate);
  });
  const lastUpdatedAt = records.map(record => record.updatedAt).filter(value => typeof value === "string" && value)
    .sort().at(-1) ?? null;

  return { summaries, lastUpdatedAt };
}

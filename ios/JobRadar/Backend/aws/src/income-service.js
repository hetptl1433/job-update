import { HTTPError } from "./errors.js";
import {
  buildIncomeOverview,
  INCOME_SOURCE_TYPES,
  isValidDateOnly,
  normalizedIncomeDescriptor
} from "./income.js";
import { listUserRecords, saveIncomeClassification } from "./store.js";

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function rejectUnknownKeys(value, allowed) {
  const unknown = Object.keys(value).filter(key => !allowed.has(key));
  if (unknown.length > 0) throw new HTTPError(400, `Unknown request field: ${unknown[0]}.`);
}

export function validateIncomeRequest(value) {
  if (!plainObject(value)) throw new HTTPError(400, "The income request must be a JSON object.");
  rejectUnknownKeys(value, new Set(["asOfDate", "timeZone"]));
  if (!isValidDateOnly(value.asOfDate)) {
    throw new HTTPError(400, "asOfDate must be a real calendar date in YYYY-MM-DD format.");
  }
  if (typeof value.timeZone !== "string" || value.timeZone.length < 1 || value.timeZone.length > 64 ||
      !/^[A-Za-z0-9_+./-]+$/.test(value.timeZone)) {
    throw new HTTPError(400, "timeZone must be a valid IANA time-zone identifier.");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value.timeZone }).format(new Date(0));
  } catch {
    throw new HTTPError(400, "timeZone must be a valid IANA time-zone identifier.");
  }
  return { asOfDate: value.asOfDate, timeZone: value.timeZone };
}

export function validateIncomeTransactionID(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HTTPError(400, "A valid financial transaction ID is required.");
  }
  return value;
}

export function validateIncomeClassificationRequest(value) {
  if (!plainObject(value)) throw new HTTPError(400, "The classification request must be a JSON object.");
  rejectUnknownKeys(value, new Set(["classification", "sourceName", "type", "sourceType", "asOfDate", "timeZone"]));
  if (value.classification !== "income" && value.classification !== "notIncome") {
    throw new HTTPError(400, "classification must be income or notIncome.");
  }

  let sourceName;
  if (value.sourceName !== undefined) {
    if (typeof value.sourceName !== "string" || !value.sourceName.trim() || value.sourceName.length > 120 ||
        /[\u0000-\u001f\u007f]/.test(value.sourceName)) {
      throw new HTTPError(400, "sourceName must be 1 to 120 characters without control characters.");
    }
    sourceName = value.sourceName.trim();
  }

  if (value.type !== undefined && value.sourceType !== undefined && value.type !== value.sourceType) {
    throw new HTTPError(400, "type and sourceType cannot disagree.");
  }
  const sourceType = value.type ?? value.sourceType;
  if (sourceType !== undefined && !INCOME_SOURCE_TYPES.includes(sourceType)) {
    throw new HTTPError(400, `type must be one of: ${INCOME_SOURCE_TYPES.join(", ")}.`);
  }

  const localDate = validateIncomeRequest({ asOfDate: value.asOfDate, timeZone: value.timeZone });

  return { classification: value.classification, sourceName, sourceType, ...localDate };
}

export async function getIncomeOverview(userSub, request) {
  const options = validateIncomeRequest(request);
  return buildIncomeOverview(await listUserRecords(userSub), options);
}

export async function classifyIncomeTransaction(userSub, transactionID, request, dependencies = {}) {
  const validID = validateIncomeTransactionID(transactionID);
  const value = validateIncomeClassificationRequest(request);
  const loadRecords = dependencies.listUserRecords ?? listUserRecords;
  const saveClassification = dependencies.saveIncomeClassification ?? saveIncomeClassification;
  const records = await loadRecords(userSub);
  const transaction = records.find(record => record.entityType === "TRANSACTION" && record.id === validID);
  if (!transaction) throw new HTTPError(404, "That financial transaction was not found.");
  if (transaction.direction !== "inflow") {
    throw new HTTPError(409, "Only incoming transactions can be classified as income.");
  }

  const existing = records.find(record =>
    record.entityType === "INCOME_CLASSIFICATION" && record.transactionID === validID) ?? null;
  const saved = await saveClassification(userSub, transaction, {
    ...value,
    descriptor: normalizedIncomeDescriptor(transaction)
  }, existing);
  const currentRecords = records.filter(record =>
    !(record.entityType === "INCOME_CLASSIFICATION" && record.transactionID === validID));
  currentRecords.push(saved);
  return buildIncomeOverview(currentRecords, { asOfDate: value.asOfDate });
}

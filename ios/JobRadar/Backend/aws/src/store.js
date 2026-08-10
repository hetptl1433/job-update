import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { createHash } from "node:crypto";
import {
  BatchWriteCommand,
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  TransactWriteCommand,
  UpdateCommand
} from "@aws-sdk/lib-dynamodb";
import { HTTPError } from "./errors.js";

const documentClient = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true }
});

function tableName() {
  if (!process.env.FINANCE_TABLE_NAME) throw new HTTPError(500, "Missing server setting: FINANCE_TABLE_NAME.");
  return process.env.FINANCE_TABLE_NAME;
}

function userKey(userSub) {
  return `USER#${userSub}`;
}

function nowString() {
  return new Date().toISOString();
}

async function queryAll(input) {
  const items = [];
  let ExclusiveStartKey;
  do {
    const page = await documentClient.send(new QueryCommand({ ...input, ExclusiveStartKey }));
    items.push(...(page.Items ?? []));
    ExclusiveStartKey = page.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return items;
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size));
  return result;
}

async function batchWrite(requests) {
  for (const group of chunks(requests, 25)) {
    let pending = group;
    for (let attempt = 0; attempt < 5 && pending.length > 0; attempt += 1) {
      const response = await documentClient.send(new BatchWriteCommand({
        RequestItems: { [tableName()]: pending }
      }));
      pending = response.UnprocessedItems?.[tableName()] ?? [];
      if (pending.length > 0) await new Promise(resolve => setTimeout(resolve, 25 * (2 ** attempt)));
    }
    if (pending.length > 0) throw new HTTPError(503, "Finance storage is temporarily busy. Try again.");
  }
}

export async function listUserRecords(userSub) {
  return queryAll({
    TableName: tableName(),
    KeyConditionExpression: "PK = :pk",
    ExpressionAttributeValues: { ":pk": userKey(userSub) },
    ConsistentRead: true
  });
}

export async function listUserItems(userSub) {
  return (await listUserRecords(userSub)).filter(record => record.entityType === "PLAID_ITEM");
}

export async function getUserItem(userSub, itemID) {
  const response = await documentClient.send(new GetCommand({
    TableName: tableName(),
    Key: { PK: userKey(userSub), SK: `ITEM#${itemID}` },
    ConsistentRead: true
  }));
  return response.Item ?? null;
}

export async function findItemOwner(itemID) {
  const records = await queryAll({
    TableName: tableName(),
    IndexName: "GSI1",
    KeyConditionExpression: "GSI1PK = :pk",
    ExpressionAttributeValues: { ":pk": `ITEM#${itemID}` }
  });
  return records.find(record => record.entityType === "PLAID_ITEM") ?? null;
}

export async function saveHostedLinkSession(session) {
  await documentClient.send(new PutCommand({
    TableName: tableName(),
    Item: {
      PK: `HOSTED_LINK#${session.linkTokenHash}`,
      SK: "SESSION",
      GSI1PK: userKey(session.userSub),
      GSI1SK: `HOSTED_LINK#${session.connectionID}`,
      entityType: "HOSTED_LINK_SESSION",
      userSub: session.userSub,
      connectionID: session.connectionID,
      linkTokenHash: session.linkTokenHash,
      status: "pending",
      expiresAt: session.expiresAt,
      // DynamoDB TTL deletion is asynchronous. Runtime checks enforce expiresAt;
      // this later timestamp only keeps completed-session status briefly available.
      deleteAfter: session.expiresAt + 86_400,
      createdAt: nowString(),
      updatedAt: nowString()
    },
    ConditionExpression: "attribute_not_exists(PK)"
  }));
}

export async function getHostedLinkSessionByTokenHash(linkTokenHash) {
  const response = await documentClient.send(new GetCommand({
    TableName: tableName(),
    Key: { PK: `HOSTED_LINK#${linkTokenHash}`, SK: "SESSION" },
    ConsistentRead: true
  }));
  return response.Item ?? null;
}

export async function getHostedLinkSessionForUser(userSub, connectionID) {
  const records = await queryAll({
    TableName: tableName(),
    IndexName: "GSI1",
    KeyConditionExpression: "GSI1PK = :pk AND GSI1SK = :sk",
    ExpressionAttributeValues: {
      ":pk": userKey(userSub),
      ":sk": `HOSTED_LINK#${connectionID}`
    }
  });
  return records.find(record => record.entityType === "HOSTED_LINK_SESSION") ?? null;
}

export async function updateHostedLinkSession(linkTokenHash, status, values = {}) {
  const names = { "#status": "status" };
  const expressionValues = {
    ":status": status,
    ":updated": nowString()
  };
  const sets = ["#status = :status", "updatedAt = :updated"];

  for (const [name, value] of Object.entries(values)) {
    if (value === undefined) continue;
    names[`#${name}`] = name;
    expressionValues[`:${name}`] = value;
    sets.push(`#${name} = :${name}`);
  }

  await documentClient.send(new UpdateCommand({
    TableName: tableName(),
    Key: { PK: `HOSTED_LINK#${linkTokenHash}`, SK: "SESSION" },
    UpdateExpression: `SET ${sets.join(", ")}`,
    ExpressionAttributeNames: names,
    ExpressionAttributeValues: expressionValues,
    ConditionExpression: "attribute_exists(PK)"
  }));
}

export async function claimHostedPublicToken(session, publicTokenHash) {
  const now = Math.floor(Date.now() / 1000);
  try {
    await documentClient.send(new UpdateCommand({
      TableName: tableName(),
      Key: { PK: `HOSTED_PUBLIC_TOKEN#${publicTokenHash}`, SK: "CLAIM" },
      UpdateExpression: [
        "SET entityType = :entityType",
        "userSub = :userSub",
        "linkTokenHash = :linkTokenHash",
        "publicTokenHash = :publicTokenHash",
        "#status = :processing",
        "leaseUntil = :leaseUntil",
        "deleteAfter = :deleteAfter",
        "createdAt = if_not_exists(createdAt, :createdAt)",
        "updatedAt = :updatedAt"
      ].join(", "),
      ExpressionAttributeNames: { "#status": "status" },
      ExpressionAttributeValues: {
        ":entityType": "HOSTED_PUBLIC_TOKEN_CLAIM",
        ":userSub": session.userSub,
        ":linkTokenHash": session.linkTokenHash,
        ":publicTokenHash": publicTokenHash,
        ":processing": "processing",
        // Lambda times out at 29 seconds. A 60-second lease prevents concurrent
        // exchange while allowing Plaid's later retry to recover after a crash.
        ":leaseUntil": now + 60,
        ":deleteAfter": session.expiresAt + 86_400,
        ":createdAt": nowString(),
        ":updatedAt": nowString(),
        ":now": now
      },
      ConditionExpression: "attribute_not_exists(PK) OR leaseUntil < :now"
    }));
    return true;
  } catch (error) {
    if (error?.name === "ConditionalCheckFailedException") return false;
    throw error;
  }
}

export async function completeHostedPublicToken(publicTokenHash) {
  await documentClient.send(new UpdateCommand({
    TableName: tableName(),
    Key: { PK: `HOSTED_PUBLIC_TOKEN#${publicTokenHash}`, SK: "CLAIM" },
    UpdateExpression: "SET #status = :status, updatedAt = :updated REMOVE leaseUntil",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: { ":status": "complete", ":updated": nowString() },
    ConditionExpression: "attribute_exists(PK)"
  }));
}

export async function releaseHostedPublicToken(publicTokenHash) {
  await documentClient.send(new DeleteCommand({
    TableName: tableName(),
    Key: { PK: `HOSTED_PUBLIC_TOKEN#${publicTokenHash}`, SK: "CLAIM" }
  }));
}

export async function savePlaidItem(userSub, item) {
  const existing = await getUserItem(userSub, item.itemID);
  await documentClient.send(new PutCommand({
    TableName: tableName(),
    Item: {
      PK: userKey(userSub),
      SK: `ITEM#${item.itemID}`,
      GSI1PK: `ITEM#${item.itemID}`,
      GSI1SK: userKey(userSub),
      entityType: "PLAID_ITEM",
      userSub,
      itemID: item.itemID,
      institutionID: item.institutionID ?? null,
      institutionName: item.institutionName,
      accessTokenCiphertext: item.accessTokenCiphertext,
      cursor: existing?.cursor ?? null,
      needsAttention: false,
      createdAt: existing?.createdAt ?? nowString(),
      updatedAt: nowString()
    }
  }));
}

export async function saveAccounts(userSub, item, accounts) {
  const existing = await listUserRecords(userSub);
  const currentIDs = new Set(accounts.map(account => account.id));
  const stale = existing.filter(record =>
    record.itemID === item.itemID && (
      (record.entityType === "ACCOUNT" && !currentIDs.has(record.id)) ||
      (record.entityType === "TRANSACTION" && !currentIDs.has(record.accountID)) ||
      (record.entityType === "INCOME_CLASSIFICATION" && !currentIDs.has(record.accountID))
    )
  );

  const writes = accounts.map(account => ({
    PutRequest: {
      Item: {
        PK: userKey(userSub),
        SK: `ACCOUNT#${account.id}`,
        entityType: "ACCOUNT",
        ...account,
        updatedAt: nowString()
      }
    }
  }));
  writes.push(...stale.map(record => ({ DeleteRequest: { Key: { PK: record.PK, SK: record.SK } } })));
  if (writes.length > 0) await batchWrite(writes);
}

export function incomeClassificationSortKey(transactionID) {
  return `INCOME_CLASSIFICATION#${createHash("sha256").update(transactionID, "utf8").digest("hex")}`;
}

export async function saveIncomeClassification(userSub, transaction, value, existing = null) {
  const timestamp = nowString();
  const item = {
    PK: userKey(userSub),
    SK: incomeClassificationSortKey(transaction.id),
    entityType: "INCOME_CLASSIFICATION",
    userSub,
    itemID: transaction.itemID,
    accountID: transaction.accountID,
    transactionID: transaction.id,
    transactionDate: transaction.date,
    descriptor: value.descriptor,
    classification: value.classification,
    sourceName: value.sourceName,
    sourceType: value.sourceType,
    createdAt: existing?.createdAt ?? timestamp,
    updatedAt: timestamp
  };
  try {
    await documentClient.send(new TransactWriteCommand({
      TransactItems: [
        {
          ConditionCheck: {
            TableName: tableName(),
            Key: { PK: userKey(userSub), SK: `TRANSACTION#${transaction.id}` },
            ConditionExpression: "entityType = :transaction AND accountID = :account AND direction = :inflow",
            ExpressionAttributeValues: {
              ":transaction": "TRANSACTION",
              ":account": transaction.accountID,
              ":inflow": "inflow"
            }
          }
        },
        { Put: { TableName: tableName(), Item: item } }
      ]
    }));
  } catch (error) {
    if (error?.name === "TransactionCanceledException") {
      throw new HTTPError(409, "That transaction changed while it was being classified. Refresh and try again.");
    }
    throw error;
  }
  return item;
}

export async function applyTransactionChanges(userSub, itemID, changes) {
  const timestamp = nowString();
  const writes = [...changes.added, ...changes.modified].map(transaction => ({
    PutRequest: {
      Item: {
        PK: userKey(userSub),
        SK: `TRANSACTION#${transaction.id}`,
        entityType: "TRANSACTION",
        itemID,
        ...transaction,
        updatedAt: timestamp
      }
    }
  }));
  writes.push(...changes.removed.map(transaction => ({
    DeleteRequest: {
      Key: { PK: userKey(userSub), SK: `TRANSACTION#${transaction.transaction_id}` }
    }
  })));
  if (writes.length > 0) await batchWrite(writes);
}

export async function updateItemSyncState(userSub, itemID, cursor) {
  await documentClient.send(new UpdateCommand({
    TableName: tableName(),
    Key: { PK: userKey(userSub), SK: `ITEM#${itemID}` },
    UpdateExpression: "SET #cursor = :cursor, needsAttention = :attention, updatedAt = :updated",
    ExpressionAttributeNames: { "#cursor": "cursor" },
    ExpressionAttributeValues: {
      ":cursor": cursor,
      ":attention": false,
      ":updated": nowString()
    },
    ConditionExpression: "attribute_exists(PK)"
  }));
}

export async function markItemNeedsAttention(userSub, itemID, needsAttention = true) {
  await documentClient.send(new UpdateCommand({
    TableName: tableName(),
    Key: { PK: userKey(userSub), SK: `ITEM#${itemID}` },
    UpdateExpression: "SET needsAttention = :attention, updatedAt = :updated",
    ExpressionAttributeValues: {
      ":attention": needsAttention,
      ":updated": nowString()
    },
    ConditionExpression: "attribute_exists(PK)"
  }));
}

export async function deleteItemData(userSub, itemID) {
  const records = (await listUserRecords(userSub)).filter(record => record.itemID === itemID);
  if (records.length === 0) return;
  await batchWrite(records.map(record => ({
    DeleteRequest: { Key: { PK: record.PK, SK: record.SK } }
  })));
}

export async function deleteUserItemRecord(userSub, itemID) {
  await documentClient.send(new DeleteCommand({
    TableName: tableName(),
    Key: { PK: userKey(userSub), SK: `ITEM#${itemID}` }
  }));
}

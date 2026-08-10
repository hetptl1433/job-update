import { KMSClient, EncryptCommand, DecryptCommand } from "@aws-sdk/client-kms";
import { HTTPError } from "./errors.js";

const kms = new KMSClient({});

function encryptionContext(userSub, itemID) {
  return {
    orbitPurpose: "plaid-item-access-token",
    orbitUser: userSub,
    plaidItem: itemID
  };
}

function keyID() {
  const value = process.env.TOKEN_KMS_KEY_ID;
  if (!value) throw new HTTPError(500, "Missing server setting: TOKEN_KMS_KEY_ID.");
  return value;
}

export async function encryptAccessToken(accessToken, userSub, itemID) {
  const result = await kms.send(new EncryptCommand({
    KeyId: keyID(),
    Plaintext: Buffer.from(accessToken, "utf8"),
    EncryptionContext: encryptionContext(userSub, itemID)
  }));
  if (!result.CiphertextBlob) throw new HTTPError(500, "Could not protect the Plaid access token.");
  return Buffer.from(result.CiphertextBlob).toString("base64");
}

export async function decryptAccessToken(ciphertext, userSub, itemID) {
  const result = await kms.send(new DecryptCommand({
    KeyId: keyID(),
    CiphertextBlob: Buffer.from(ciphertext, "base64"),
    EncryptionContext: encryptionContext(userSub, itemID)
  }));
  if (!result.Plaintext) throw new HTTPError(500, "Could not unlock the Plaid access token.");
  return Buffer.from(result.Plaintext).toString("utf8");
}

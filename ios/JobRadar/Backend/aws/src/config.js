import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { Configuration, PlaidApi, PlaidEnvironments } from "plaid";
import { HTTPError } from "./errors.js";

const secrets = new SecretsManagerClient({});
let configPromise;
let clientPromise;

function required(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HTTPError(500, `Missing server setting: ${name}.`);
  }
  return value.trim();
}

export function plaidEnvironment() {
  const value = process.env.PLAID_ENV ?? "sandbox";
  if (value !== "sandbox" && value !== "production") {
    throw new HTTPError(500, "PLAID_ENV must be sandbox or production.");
  }
  return value;
}

export async function getServerConfig() {
  configPromise ??= (async () => {
    const secretARN = required(process.env.PLAID_SECRET_ARN, "PLAID_SECRET_ARN");
    const response = await secrets.send(new GetSecretValueCommand({ SecretId: secretARN }));
    if (!response.SecretString) throw new HTTPError(500, "The Plaid secret has no text value.");

    let value;
    try {
      value = JSON.parse(response.SecretString);
    } catch {
      throw new HTTPError(500, "The Plaid secret must be stored as JSON key/value pairs.");
    }

    return Object.freeze({
      clientID: required(value.PLAID_CLIENT_ID ?? value.client_id, "PLAID_CLIENT_ID"),
      secret: required(value.PLAID_SECRET ?? value.secret, "PLAID_SECRET"),
      environment: plaidEnvironment(),
      redirectURI: required(process.env.PLAID_REDIRECT_URI, "PLAID_REDIRECT_URI"),
      webhookURL: required(process.env.PLAID_WEBHOOK_URL, "PLAID_WEBHOOK_URL"),
      hostedLinkCompletionURI: required(
        process.env.HOSTED_LINK_COMPLETION_URI ?? "orbit://finance",
        "HOSTED_LINK_COMPLETION_URI"
      )
    });
  })();
  return configPromise;
}

export async function getPlaidClient() {
  clientPromise ??= (async () => {
    const config = await getServerConfig();
    const basePath = PlaidEnvironments[config.environment];
    return new PlaidApi(new Configuration({
      basePath,
      baseOptions: {
        headers: {
          "PLAID-CLIENT-ID": config.clientID,
          "PLAID-SECRET": config.secret
        }
      }
    }));
  })();
  return clientPromise;
}

export function resetConfigForTests() {
  configPromise = undefined;
  clientPromise = undefined;
}

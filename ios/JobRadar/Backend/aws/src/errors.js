export class HTTPError extends Error {
  constructor(statusCode, message, options = {}) {
    super(message, options);
    this.name = "HTTPError";
    this.statusCode = statusCode;
  }
}

export function plaidErrorCode(error) {
  return error?.response?.data?.error_code ?? error?.response?.data?.error_type ?? null;
}

export function plaidRequestID(error) {
  return error?.response?.data?.request_id ?? null;
}

export function publicError(error) {
  if (error instanceof HTTPError) return error;

  switch (plaidErrorCode(error)) {
  case "ITEM_LOGIN_REQUIRED":
  case "PENDING_DISCONNECT":
    return new HTTPError(409, "This bank connection needs attention. Reconnect it from Finance.");
  case "PRODUCT_NOT_READY":
    return new HTTPError(409, "Plaid is still preparing this account. Try refreshing again shortly.");
  case "INSTITUTION_DOWN":
  case "INSTITUTION_NOT_RESPONDING":
    return new HTTPError(503, "The financial institution is temporarily unavailable.");
  case "INVALID_API_KEYS":
    return new HTTPError(502, "Plaid rejected Orbit's server credentials.");
  case "INVALID_FIELD":
  case "INVALID_CONFIGURATION":
    return new HTTPError(502, "Orbit's Plaid server configuration is incomplete.");
  default:
    return new HTTPError(500, "Orbit Finance could not complete the request.");
  }
}

export function safeErrorLog(error, routeKey) {
  return {
    route: routeKey,
    name: error?.name ?? "Error",
    code: plaidErrorCode(error),
    plaidRequestID: plaidRequestID(error)
  };
}

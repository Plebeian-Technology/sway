/** @format */

export const API_PREFIX = "sway";
const API_NO_AUTH = "open";
const API_AUTHED = "auth";
const API_VERSION = "v1";

const PORT = 3000;

export const BASE_API_URL = {
  localhost: `https://localhost:${PORT}`,
}[window.location.hostname] as string;

export const BASE_NO_AUTH_API_ROUTE_V1 = ""
export const BASE_AUTHED_ROUTE_V1 = ""
// export const BASE_NO_AUTH_API_ROUTE_V1 = `${API_PREFIX}/${API_NO_AUTH}/${API_VERSION}`;
// export const BASE_AUTHED_ROUTE_V1 = `${API_PREFIX}/${API_AUTHED}/${API_VERSION}`;

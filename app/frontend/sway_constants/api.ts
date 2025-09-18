/** @format */

export const API_PREFIX = "sway/api";
const NO_AUTH = "open";
const AUTHED = "auth";
// const API_VERSION = "v1";

const PORT = 3333;
// const PORT = 8443;

export const BASE_API_URL = {
    localhost: `https://localhost:${PORT}`,
}[window.location.hostname] as string;

export const BASE_NO_AUTH_API_ROUTE_V1 = `${API_PREFIX}/${NO_AUTH}`;
export const BASE_AUTHED_ROUTE_V1 = `${API_PREFIX}/${AUTHED}`;

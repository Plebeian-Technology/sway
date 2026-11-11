// @lat: [[mobile-secure-store-key-separation#sessionStore: the whole session record, so signOut can revoke the device]]
import Constants from "expo-constants";

interface ExtraConfig {
    apiBaseUrl?: string;
}

const extra = (Constants.expoConfig?.extra ?? {}) as ExtraConfig;

export const API_BASE_URL: string = extra.apiBaseUrl ?? "https://app.sway.vote";

// @lat: [[mobile-secure-store-key-separation#tokenStore: only the bearer token, on purpose]]
export const BEARER_TOKEN_KEY = "sway_bearer_token";

export const SESSION_ENVELOPE_KEY = "sway.session";

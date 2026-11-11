// @lat: [[mobile-secure-store-key-separation#tokenStore: only the bearer token, on purpose]]
import * as SecureStore from "expo-secure-store";
import { BEARER_TOKEN_KEY } from "../constants/api";

const MAX_BYTES = 2048;

export const tokenStore = {
    async get(): Promise<string | null> {
        return await SecureStore.getItemAsync(BEARER_TOKEN_KEY);
    },

    async set(token: string): Promise<void> {
        if (token.length > MAX_BYTES) {
            throw new Error(`bearer token too large for SecureStore (>${MAX_BYTES} bytes)`);
        }
        await SecureStore.setItemAsync(BEARER_TOKEN_KEY, token, {
            keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
        });
    },

    async clear(): Promise<void> {
        await SecureStore.deleteItemAsync(BEARER_TOKEN_KEY);
    },
};

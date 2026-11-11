// @lat: [[mobile-secure-store-key-separation#sessionStore: the whole session record, so signOut can revoke the device]]
import * as SecureStore from "expo-secure-store";
import { SESSION_ENVELOPE_KEY } from "../constants/api";

export interface SessionEnvelope {
    bearer_token: string;
    device_id: number;
    user_id: number;
    expires_at: string;
}

const MAX_BYTES = 2048;

export const sessionStore = {
    async get(): Promise<SessionEnvelope | null> {
        // @lat: [[mobile-secure-store-key-separation#sessionStore: the whole session record, so signOut can revoke the device]]
        let raw: string | null;
        try {
            raw = await SecureStore.getItemAsync(SESSION_ENVELOPE_KEY);
        } catch (e) {
            // oxlint-disable-next-line no-console
            console.error("sessionStore: keychain read failed", e);
            return null;
        }
        if (!raw) return null;
        try {
            return JSON.parse(raw) as SessionEnvelope;
        } catch {
            // @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]
            return null;
        }
    },

    async set(env: SessionEnvelope): Promise<void> {
        const serialized = JSON.stringify(env);
        if (serialized.length > MAX_BYTES) {
            throw new Error(`session envelope too large for SecureStore (>${MAX_BYTES} bytes)`);
        }
        await SecureStore.setItemAsync(SESSION_ENVELOPE_KEY, serialized, {
            keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
        });
    },

    async clear(): Promise<void> {
        await SecureStore.deleteItemAsync(SESSION_ENVELOPE_KEY);
    },
};

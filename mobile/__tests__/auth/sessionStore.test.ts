/**
 * sessionStore — keeps the whole session together in one bundle.
 * Saves { bearer_token, device_id, user_id, expires_at } under the key
 * "sway.session".
 */
import * as SecureStore from "expo-secure-store";
import { sessionStore, SessionEnvelope } from "../../src/auth/sessionStore";
import { SESSION_ENVELOPE_KEY } from "../../src/constants/api";

const sample: SessionEnvelope = {
    bearer_token: "tk_abc",
    device_id: 42,
    user_id: 7,
    expires_at: "2026-12-31T00:00:00Z",
};

describe("sessionStore", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("reads as no session when the keychain item cannot be read", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockRejectedValueOnce(new Error("keychain unavailable"));
        const consoleError = jest.spyOn(console, "error").mockImplementation(() => {});

        await expect(sessionStore.get()).resolves.toBeNull();

        consoleError.mockRestore();
    });

    test("set + get round-trip preserves envelope fields", async () => {
        let stored: string | null = null;
        (SecureStore.setItemAsync as jest.Mock).mockImplementation(async (_k, v) => {
            stored = v;
        });
        (SecureStore.getItemAsync as jest.Mock).mockImplementation(async () => stored);

        await sessionStore.set(sample);
        expect(SecureStore.setItemAsync).toHaveBeenCalledWith(
            SESSION_ENVELOPE_KEY,
            JSON.stringify(sample),
            expect.objectContaining({
                keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
            }),
        );
        const out = await sessionStore.get();
        expect(out).toEqual(sample);
    });

    test("get returns null when never set", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValueOnce(null);
        const v = await sessionStore.get();
        expect(v).toBeNull();
    });

    test("clear removes the envelope", async () => {
        await sessionStore.clear();
        expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith(SESSION_ENVELOPE_KEY);
    });

    test("set throws when serialized envelope > 2048 bytes", async () => {
        const huge: SessionEnvelope = {
            ...sample,
            bearer_token: "x".repeat(3000),
        };
        await expect(sessionStore.set(huge)).rejects.toThrow(/too large/i);
        expect(SecureStore.setItemAsync).not.toHaveBeenCalled();
    });

    test("get returns null on malformed JSON", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValueOnce("{not-json");
        const v = await sessionStore.get();
        expect(v).toBeNull();
    });
});

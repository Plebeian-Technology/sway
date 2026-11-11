/**
 * tokenStore — holds the bearer token and nothing else.
 * A thin wrapper around expo-secure-store, using the key "sway_bearer_token".
 */
import * as SecureStore from "expo-secure-store";
import { tokenStore } from "../../src/auth/tokenStore";
import { BEARER_TOKEN_KEY } from "../../src/constants/api";

describe("tokenStore", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("get returns null initially", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValueOnce(null);
        const v = await tokenStore.get();
        expect(v).toBeNull();
        expect(SecureStore.getItemAsync).toHaveBeenCalledWith(BEARER_TOKEN_KEY);
    });

    test("set + get round-trip persists token under sway_bearer_token", async () => {
        const token = "abc123hex";
        await tokenStore.set(token);
        expect(SecureStore.setItemAsync).toHaveBeenCalledWith(
            BEARER_TOKEN_KEY,
            token,
            expect.objectContaining({
                keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
            }),
        );
    });

    test("set throws when token > 2048 bytes (SecureStore limit)", async () => {
        const big = "x".repeat(2049);
        await expect(tokenStore.set(big)).rejects.toThrow(/too large/i);
        expect(SecureStore.setItemAsync).not.toHaveBeenCalled();
    });

    test("clear removes the bearer key", async () => {
        await tokenStore.clear();
        expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith(BEARER_TOKEN_KEY);
    });
});

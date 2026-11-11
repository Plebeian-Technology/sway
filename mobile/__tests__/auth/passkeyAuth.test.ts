// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
import { Passkey } from "react-native-passkey";
import { Platform } from "react-native";

import { passkeyAuth, PasskeyUnsupportedError, NoPasskeyError } from "../../src/auth/passkeyAuth";
import { apiClient } from "../../src/api/client";
import { tokenStore } from "../../src/auth/tokenStore";
import { sessionStore } from "../../src/auth/sessionStore";
import { authEvents } from "../../src/auth/authEvents";
import { ApiRequestError } from "../../src/api/errors";

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(),
        post: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

jest.mock("../../src/auth/tokenStore", () => ({
    tokenStore: {
        get: jest.fn(),
        set: jest.fn(async () => {}),
        clear: jest.fn(async () => {}),
    },
}));

jest.mock("../../src/auth/sessionStore", () => ({
    sessionStore: {
        get: jest.fn(),
        set: jest.fn(async () => {}),
        clear: jest.fn(async () => {}),
    },
}));

const callbackResp = {
    bearer_token: "tk_xyz",
    device_id: 999,
    user: { id: 7, phone: "+15551112222" },
    expires_at: "2026-12-31T00:00:00Z",
};

const getOptions = {
    challenge: "raw-challenge",
    rpId: "app.sway.vote",
    allowCredentials: [],
};

// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
const passkeyFlow = { flow: "passkey", challenge_id: "ch_42", options: getOptions };

const challengeOpts = {
    challenge_id: "ch_42",
    challenge: "raw-challenge",
    rp_id: "app.sway.vote",
    allow_credentials: [],
};

describe("passkeyAuth", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        (Passkey.isSupported as jest.Mock).mockReturnValue(true);
        (Passkey.get as jest.Mock).mockResolvedValue({
            id: "cred-1",
            rawId: "cred-1",
            response: {},
            type: "public-key",
        });
        (Passkey.create as jest.Mock).mockResolvedValue({
            id: "cred-1",
            rawId: "cred-1",
            response: {},
            type: "public-key",
        });
    });

    describe("signIn", () => {
        test("calls /sessions/challenge → Passkey.get → /sessions/callback and persists tokenStore + sessionStore (D2)", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(passkeyFlow).mockResolvedValueOnce(callbackResp);

            const emitSpy = jest.spyOn(authEvents, "emit");

            const result = await passkeyAuth.signIn("+15551112222");

            expect(apiClient.post).toHaveBeenNthCalledWith(1, "/api/v1/sessions/challenge", {
                session: { phone: "+15551112222" },
            });
            expect(Passkey.get).toHaveBeenCalledWith(getOptions);
            expect(apiClient.post).toHaveBeenNthCalledWith(
                2,
                "/api/v1/sessions/callback",
                expect.objectContaining({
                    session: expect.objectContaining({
                        challenge_id: "ch_42",
                        platform: Platform.OS,
                        credential: expect.objectContaining({ id: "cred-1" }),
                    }),
                }),
            );
            expect(tokenStore.set).toHaveBeenCalledWith("tk_xyz");
            expect(sessionStore.set).toHaveBeenCalledWith({
                bearer_token: "tk_xyz",
                device_id: 999,
                user_id: 7,
                expires_at: "2026-12-31T00:00:00Z",
            });
            expect(emitSpy).toHaveBeenCalledWith("signed_in");
            expect(result.user.id).toBe(7);
        });

        test("throws PasskeyUnsupportedError when Passkey.isSupported() is false", async () => {
            (Passkey.isSupported as jest.Mock).mockReturnValue(false);
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toBeInstanceOf(PasskeyUnsupportedError);
            expect(apiClient.post).not.toHaveBeenCalled();
        });

        // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
        test("throws NoPasskeyError without running a ceremony when the server answers flow: sms", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce({ flow: "sms" });

            await expect(passkeyAuth.signIn("+15551112222")).rejects.toBeInstanceOf(NoPasskeyError);
            expect(Passkey.get).not.toHaveBeenCalled();
            expect(apiClient.post).toHaveBeenCalledTimes(1);
        });

        test("throws NoPasskeyError when /sessions/challenge returns no_passkey_enrolled", async () => {
            (apiClient.post as jest.Mock).mockRejectedValueOnce(
                new ApiRequestError("no_passkey_enrolled", "no passkey", undefined, 404),
            );
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toBeInstanceOf(NoPasskeyError);
        });

        // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
        test.each([
            ["UserCancelled", "The user cancelled the request."],
            ["NoCredentials", "No viable credential is available for the user."],
        ])("maps the thrown {error: %s} object → NoPasskeyError, so the SMS fallback runs", async (error, message) => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(passkeyFlow);
            (Passkey.get as jest.Mock).mockRejectedValueOnce({ error, message });
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toBeInstanceOf(NoPasskeyError);
        });

        test("maps the thrown {error: NotSupported} object → PasskeyUnsupportedError", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(passkeyFlow);
            (Passkey.get as jest.Mock).mockRejectedValueOnce({
                error: "NotSupported",
                message: "Passkeys are not supported on this device.",
            });
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toBeInstanceOf(PasskeyUnsupportedError);
        });

        test.each(["RequestFailed", "BadConfiguration"])(
            "leaves %s unmapped, so an rp_id mismatch stays visible",
            async (error) => {
                (apiClient.post as jest.Mock).mockResolvedValueOnce(passkeyFlow);
                (Passkey.get as jest.Mock).mockRejectedValueOnce({ error, message: "nope" });
                await expect(passkeyAuth.signIn("+15551112222")).rejects.not.toBeInstanceOf(NoPasskeyError);
            },
        );

        test("surfaces the library's message when the outcome is not one we map", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(passkeyFlow);
            (Passkey.get as jest.Mock).mockRejectedValueOnce({
                error: "RequestFailed",
                message: "The request failed. No Credentials were returned.",
            });
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toThrow(
                "The request failed. No Credentials were returned.",
            );
        });

        test("does NOT persist session if /sessions/callback fails", async () => {
            (apiClient.post as jest.Mock)
                .mockResolvedValueOnce(passkeyFlow)
                .mockRejectedValueOnce(new ApiRequestError("boom", "boom"));
            await expect(passkeyAuth.signIn("+15551112222")).rejects.toThrow();
            expect(tokenStore.set).not.toHaveBeenCalled();
            expect(sessionStore.set).not.toHaveBeenCalled();
        });
    });

    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
    describe("signInDiscoverable", () => {
        test("calls /sessions/discoverable_challenge with no phone → Passkey.get → /sessions/callback → persists", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(challengeOpts).mockResolvedValueOnce(callbackResp);
            const emitSpy = jest.spyOn(authEvents, "emit");

            const result = await passkeyAuth.signInDiscoverable();

            expect(apiClient.post).toHaveBeenNthCalledWith(1, "/api/v1/sessions/discoverable_challenge", {});
            expect(Passkey.get).toHaveBeenCalledWith(challengeOpts);
            expect(apiClient.post).toHaveBeenNthCalledWith(
                2,
                "/api/v1/sessions/callback",
                expect.objectContaining({
                    session: expect.objectContaining({
                        challenge_id: "ch_42",
                        platform: Platform.OS,
                        credential: expect.objectContaining({ id: "cred-1" }),
                    }),
                }),
            );
            expect(tokenStore.set).toHaveBeenCalledWith("tk_xyz");
            expect(emitSpy).toHaveBeenCalledWith("signed_in");
            expect(result.user.id).toBe(7);
        });

        test("throws PasskeyUnsupportedError when Passkey.isSupported() is false", async () => {
            (Passkey.isSupported as jest.Mock).mockReturnValue(false);
            await expect(passkeyAuth.signInDiscoverable()).rejects.toBeInstanceOf(PasskeyUnsupportedError);
            expect(apiClient.post).not.toHaveBeenCalled();
        });

        test("maps a cancelled / no-credential ceremony to NoPasskeyError (fall back to phone)", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(challengeOpts);
            (Passkey.get as jest.Mock).mockRejectedValueOnce({
                error: "UserCancelled",
                message: "The user cancelled the request.",
            });
            await expect(passkeyAuth.signInDiscoverable()).rejects.toBeInstanceOf(NoPasskeyError);
        });
    });

    describe("register", () => {
        test("calls /registrations → Passkey.create → /registrations/callback and persists session", async () => {
            const regOpts = { ...challengeOpts, user: { id: "u_7", name: "x", displayName: "x" } };
            (apiClient.post as jest.Mock).mockResolvedValueOnce(regOpts).mockResolvedValueOnce(callbackResp);

            const emitSpy = jest.spyOn(authEvents, "emit");

            const result = await passkeyAuth.register("+15551112222", "smsv_token_abc");

            expect(apiClient.post).toHaveBeenNthCalledWith(1, "/api/v1/registrations", {
                registration: { sms_verified_token: "smsv_token_abc", phone: "+15551112222" },
            });
            expect(Passkey.create).toHaveBeenCalledWith(regOpts);
            expect(apiClient.post).toHaveBeenNthCalledWith(
                2,
                "/api/v1/registrations/callback",
                expect.objectContaining({
                    registration: expect.objectContaining({
                        challenge_id: "ch_42",
                        platform: Platform.OS,
                        credential: expect.objectContaining({ id: "cred-1" }),
                    }),
                }),
            );
            expect(tokenStore.set).toHaveBeenCalledWith("tk_xyz");
            expect(sessionStore.set).toHaveBeenCalledWith({
                bearer_token: "tk_xyz",
                device_id: 999,
                user_id: 7,
                expires_at: "2026-12-31T00:00:00Z",
            });
            expect(emitSpy).toHaveBeenCalledWith("signed_in");
            expect(result.user.id).toBe(7);
        });
    });

    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
    describe("addPasskey", () => {
        test("calls /api/v1/passkeys → Passkey.create → /api/v1/passkeys/callback with the sms token and label", async () => {
            const regOpts = { ...challengeOpts, user: { id: "u_7", name: "x", displayName: "x" } };
            (apiClient.post as jest.Mock)
                .mockResolvedValueOnce(regOpts)
                .mockResolvedValueOnce({ id: 55, label: "iPad" });

            const result = await passkeyAuth.addPasskey("smsv_token_abc", "iPad");

            expect(apiClient.post).toHaveBeenNthCalledWith(1, "/api/v1/passkeys", {
                passkey: { sms_verified_token: "smsv_token_abc", label: "iPad" },
            });
            expect(Passkey.create).toHaveBeenCalledWith(regOpts);
            expect(apiClient.post).toHaveBeenNthCalledWith(
                2,
                "/api/v1/passkeys/callback",
                expect.objectContaining({
                    passkey: expect.objectContaining({
                        challenge_id: "ch_42",
                        label: "iPad",
                        credential: expect.objectContaining({ id: "cred-1" }),
                    }),
                }),
            );
            // Adding a passkey must leave the session alone — the user stays signed in.
            expect(tokenStore.set).not.toHaveBeenCalled();
            expect(sessionStore.set).not.toHaveBeenCalled();
            expect(result).toEqual({ id: 55, label: "iPad" });
        });

        test("maps a cancelled create ceremony to NoPasskeyError", async () => {
            (apiClient.post as jest.Mock).mockResolvedValueOnce(challengeOpts);
            (Passkey.create as jest.Mock).mockRejectedValueOnce({
                error: "UserCancelled",
                message: "The user cancelled the request.",
            });
            await expect(passkeyAuth.addPasskey("smsv_token_abc", "iPad")).rejects.toBeInstanceOf(NoPasskeyError);
        });
    });

    describe("isSupported", () => {
        test("delegates to Passkey.isSupported()", () => {
            (Passkey.isSupported as jest.Mock).mockReturnValue(false);
            expect(passkeyAuth.isSupported()).toBe(false);
            (Passkey.isSupported as jest.Mock).mockReturnValue(true);
            expect(passkeyAuth.isSupported()).toBe(true);
        });
    });
});

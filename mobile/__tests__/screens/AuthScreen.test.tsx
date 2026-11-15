// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile authentication screen]]

import React from "react";
import { Linking, Platform, StyleSheet } from "react-native";
import { act, render, fireEvent, waitFor } from "@testing-library/react-native";

import {
    passkeyAuth,
    PasskeyUnsupportedError,
    PasskeyProviderMissingError,
    PasskeyCreateUnsupportedError,
    NoPasskeyError,
    SessionSaveError,
} from "../../src/auth/passkeyAuth";
import { smsAuth } from "../../src/auth/smsAuth";
import * as SecureStore from "expo-secure-store";
import { apiClient } from "../../src/api/client";
import { ApiRequestError, NetworkError, RateLimitedError, UnauthorizedError } from "../../src/api/errors";
import { authEvents } from "../../src/auth/authEvents";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const mockNavigate = jest.fn();
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ navigate: mockNavigate }),
}));

// ── Fake passkeyAuth. The error classes are written out inside the factory,
//    because it cannot reach anything declared outside itself. ───────────────
jest.mock("../../src/auth/passkeyAuth", () => {
    class PasskeyUnsupportedError extends Error {
        constructor() {
            super("passkey_unsupported");
            this.name = "PasskeyUnsupportedError";
        }
    }
    class PasskeyProviderMissingError extends Error {
        constructor() {
            super("passkey_provider_missing");
            this.name = "PasskeyProviderMissingError";
        }
    }
    class PasskeyCreateUnsupportedError extends Error {
        constructor() {
            super("passkey_create_unsupported");
            this.name = "PasskeyCreateUnsupportedError";
        }
    }
    class NoPasskeyError extends Error {
        constructor() {
            super("no_credential");
            this.name = "NoPasskeyError";
        }
    }
    class SessionSaveError extends Error {
        constructor() {
            super("This device could not save your sign-in. Sign in with your passkey.");
            this.name = "SessionSaveError";
        }
    }
    return {
        passkeyAuth: { signIn: jest.fn(), signInDiscoverable: jest.fn(), register: jest.fn() },
        PasskeyUnsupportedError,
        PasskeyProviderMissingError,
        PasskeyCreateUnsupportedError,
        NoPasskeyError,
        SessionSaveError,
    };
});

jest.mock("../../src/auth/smsAuth", () => ({
    smsAuth: { requestCode: jest.fn(), verifyCode: jest.fn() },
}));

// ── Fake expo-haptics. Needed any time the shared Pressable renders ─────────
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// Mobile-local sentences the code step shows in place of server codes and runtime text.
const CODE_STEP_MESSAGES = {
    invalidCode: "That code did not work. Check the code and try again.",
    rateLimited: "Too many attempts. Please try again later.",
    network: "Sway could not be reached. Check your connection and try again.",
    expiredToken: "Your code expired. Request a new code to continue.",
    alreadyRegistered: "This phone already has an account. Sign in with your passkey.",
    passkeyFailed: "Passkey setup failed. Please try again.",
    unavailable: "Something went wrong on our side. Please try again.",
};

// Import AuthScreen only after the fakes above are in place.
import AuthScreen from "../../src/screens/AuthScreen";

// ── ThemeProvider wrapper. Card calls useTheme(), so every render needs it ──
const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const typePhone = (getByTestId: ReturnType<typeof render>["getByTestId"], digits = "4105550199") => {
    fireEvent.changeText(getByTestId("auth-phone-field"), digits);
};

const pressSubmit = (getByTestId: ReturnType<typeof render>["getByTestId"]) => {
    fireEvent.press(getByTestId("auth-submit-cta"));
};

describe("AuthScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        authEvents._reset();
    });

    describe("after the server ended the session", () => {
        const SESSION_ENDED_NOTICE = "Your session ended. Sign in again with your passkey.";

        test("shows the notice once a 401 from the registration request returned the user to sign-in", async () => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
            global.fetch = jest.fn().mockResolvedValueOnce({
                ok: false,
                status: 401,
                text: async () => JSON.stringify({ error: { code: "unauthorized", message: "nope" } }),
            } as unknown as Response);
            await expect(apiClient.post("/sway_registration", {})).rejects.toBeInstanceOf(UnauthorizedError);

            const { getByTestId, getByText } = wrap(<AuthScreen />);

            expect(getByTestId("auth-session-ended-notice")).toBeTruthy();
            expect(getByText(SESSION_ENDED_NOTICE)).toBeTruthy();
        });

        test("shows no notice when nothing ended a session", () => {
            const { queryByTestId } = wrap(<AuthScreen />);

            expect(queryByTestId("auth-session-ended-notice")).toBeNull();
        });

        test("shows no notice after the user signed in or out since", () => {
            authEvents.emit("unauthenticated", "session_expired");
            authEvents.emit("signed_out");

            const { queryByTestId } = wrap(<AuthScreen />);

            expect(queryByTestId("auth-session-ended-notice")).toBeNull();
        });
    });

    test("renders phone FormField + 'Continue with Phone' CTA in initial state", () => {
        const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);

        expect(getByTestId("auth-phone-field")).toBeTruthy();
        expect(getByTestId("auth-submit-cta")).toBeTruthy();
        expect(getByTestId("auth-secondary-cta")).toBeTruthy();

        expect(queryByTestId("auth-code-field")).toBeNull();

        expect(getByText(PARITY_COPY.auth.passkeyPanel.continuePhone)).toBeTruthy();
        expect(getByText(PARITY_COPY.auth.passkeyPanel.previewSway)).toBeTruthy();
    });

    test("reveals code FormField after NoPasskeyError + requestCode resolves", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
        (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);

        const { getByTestId, getByText } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());

        expect(getByText(PARITY_COPY.auth.passkeyPanel.confirmCode)).toBeTruthy();
        expect(getByText(PARITY_COPY.auth.passkeyPanel.cancelCta)).toBeTruthy();

        // requestCode gets the bare digits, not the prettified phone number.
        expect(smsAuth.requestCode).toHaveBeenCalledWith("4105550199");
    });

    test("renders loading panel while signIn promise pending", async () => {
        // A promise that never settles keeps isLoading true.
        (passkeyAuth.signIn as jest.Mock).mockReturnValue(new Promise(() => {}));

        const { getByTestId, getByText } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByTestId("auth-loading-panel")).toBeTruthy());
        expect(getByText(PARITY_COPY.auth.passkeyPanel.workingOn)).toBeTruthy();
    });

    test("navigates to DeviceUnsupported on PasskeyUnsupportedError", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new PasskeyUnsupportedError());

        const { getByTestId } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith("DeviceUnsupported"));

        // It stops before the text-message path, so smsAuth.requestCode never runs.
        expect(smsAuth.requestCode).not.toHaveBeenCalled();
    });

    test("does not reveal code input if requestCode rejects", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
        (smsAuth.requestCode as jest.Mock).mockRejectedValue(new Error("network down"));

        const { getByTestId, queryByTestId, getByText } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByText(/Could not send confirmation code/i)).toBeTruthy());
        expect(queryByTestId("auth-code-field")).toBeNull();
    });

    test("verifyCode + register chain on Confirm code press", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
        (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);
        (smsAuth.verifyCode as jest.Mock).mockResolvedValue({ sms_verified_token: "tok-1", expires_at: "2099" });
        (passkeyAuth.register as jest.Mock).mockResolvedValue(undefined);

        const { getByTestId } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());

        fireEvent.changeText(getByTestId("auth-code-field"), "123456");
        pressSubmit(getByTestId);

        await waitFor(() => expect(passkeyAuth.register).toHaveBeenCalledWith("4105550199", "tok-1"));
        expect(smsAuth.verifyCode).toHaveBeenCalledWith("4105550199", "123456");
    });

    test("pressing Confirm code with an empty code does not verify or re-trigger signIn", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
        (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);

        const { getByTestId } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
        expect(passkeyAuth.signIn).toHaveBeenCalledTimes(1);

        pressSubmit(getByTestId);

        expect(smsAuth.verifyCode).not.toHaveBeenCalled();
        expect(passkeyAuth.signIn).toHaveBeenCalledTimes(1);
    });

    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
    test("a cancelled passkey enrolment leaves the code box up with no raw error text", async () => {
        (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
        (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);
        (smsAuth.verifyCode as jest.Mock).mockResolvedValue({ sms_verified_token: "tok-1", expires_at: "2099" });
        (passkeyAuth.register as jest.Mock).mockRejectedValue(new NoPasskeyError());

        const { getByTestId, queryByText } = wrap(<AuthScreen />);

        typePhone(getByTestId);
        pressSubmit(getByTestId);

        await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());

        fireEvent.changeText(getByTestId("auth-code-field"), "123456");
        pressSubmit(getByTestId);

        await waitFor(() => expect(passkeyAuth.register).toHaveBeenCalled());
        expect(queryByText("no_credential")).toBeNull();
        expect(queryByText(PARITY_COPY.auth.passkeyPanel.verifyError)).toBeNull();
        expect(getByTestId("auth-code-field")).toBeTruthy();
    });

    describe("held SMS-verified token", () => {
        const reachCodeBox = async (getByTestId: ReturnType<typeof render>["getByTestId"]) => {
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
        };

        const confirmCode = async (getByTestId: ReturnType<typeof render>["getByTestId"], code = "123456") => {
            fireEvent.changeText(getByTestId("auth-code-field"), code);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-loading-panel")).toBeTruthy());
            await waitFor(() => expect(() => getByTestId("auth-loading-panel")).toThrow());
        };

        beforeEach(() => {
            (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
            (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);
            (smsAuth.verifyCode as jest.Mock).mockResolvedValue({ sms_verified_token: "tok-1", expires_at: "2099" });
        });

        test.each([
            ["a cancelled passkey sheet", () => new NoPasskeyError()],
            ["a generic error", () => new Error("boom")],
            ["an unsupported device", () => new PasskeyUnsupportedError()],
        ])("retries register with the held token after %s, checking the code once", async (_label, makeError) => {
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(makeError()).mockResolvedValueOnce(undefined);
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await confirmCode(getByTestId);
            await confirmCode(getByTestId);

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(1);
            expect(passkeyAuth.register).toHaveBeenCalledTimes(2);
            expect(passkeyAuth.register).toHaveBeenNthCalledWith(1, "4105550199", "tok-1");
            expect(passkeyAuth.register).toHaveBeenNthCalledWith(2, "4105550199", "tok-1");
        });

        test("clears the held token after a successful register", async () => {
            (passkeyAuth.register as jest.Mock).mockResolvedValue(undefined);
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await confirmCode(getByTestId);
            await confirmCode(getByTestId, "654321");

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
            expect(smsAuth.verifyCode).toHaveBeenLastCalledWith("4105550199", "654321");
        });

        test("Cancel clears the held token", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(new NoPasskeyError());
            (passkeyAuth.register as jest.Mock).mockResolvedValue(undefined);
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);
            await confirmCode(getByTestId);

            fireEvent.press(getByTestId("auth-secondary-cta"));
            await reachCodeBox(getByTestId);
            await confirmCode(getByTestId, "654321");

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
        });

        test("a failing verifyCode holds nothing, so the next press checks the code again", async () => {
            (smsAuth.verifyCode as jest.Mock)
                .mockRejectedValueOnce(new Error("invalid code"))
                .mockResolvedValueOnce({ sms_verified_token: "tok-2", expires_at: "2099" });
            (passkeyAuth.register as jest.Mock).mockResolvedValue(undefined);
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await confirmCode(getByTestId);
            await confirmCode(getByTestId);

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
            expect(passkeyAuth.register).toHaveBeenCalledTimes(1);
            expect(passkeyAuth.register).toHaveBeenCalledWith("4105550199", "tok-2");
        });

        test("an expired held token is dropped, so the next press checks the code again", async () => {
            (passkeyAuth.register as jest.Mock)
                .mockRejectedValueOnce(
                    new ApiRequestError(
                        "invalid_sms_token",
                        "SMS verification token invalid or expired",
                        undefined,
                        401,
                    ),
                )
                .mockResolvedValue(undefined);
            const { getByTestId, getByText } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await confirmCode(getByTestId);
            expect(getByText(CODE_STEP_MESSAGES.expiredToken)).toBeTruthy();
            await reachCodeBox(getByTestId);
            await confirmCode(getByTestId);

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
        });
    });

    describe("code step failures", () => {
        const reachCodeBox = async (getByTestId: ReturnType<typeof render>["getByTestId"]) => {
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
        };

        const pressConfirmCode = async (getByTestId: ReturnType<typeof render>["getByTestId"]) => {
            fireEvent.changeText(getByTestId("auth-code-field"), "123456");
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-loading-panel")).toBeTruthy());
            await waitFor(() => expect(() => getByTestId("auth-loading-panel")).toThrow());
        };

        const rawText = "raw server or runtime text";
        const serverError = (Klass: typeof ApiRequestError, code: string, status: number) =>
            new Klass(code, rawText, undefined, status);

        beforeEach(() => {
            (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
            (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);
            (smsAuth.verifyCode as jest.Mock).mockResolvedValue({ sms_verified_token: "tok-1", expires_at: "2099" });
            (passkeyAuth.register as jest.Mock).mockResolvedValue(undefined);
        });

        test.each([
            [
                "a wrong code",
                "verify",
                () => serverError(UnauthorizedError, "invalid_code", 401),
                CODE_STEP_MESSAGES.invalidCode,
            ],
            [
                "too many attempts on the code check",
                "verify",
                () => serverError(RateLimitedError, "rate_limited", 429),
                CODE_STEP_MESSAGES.rateLimited,
            ],
            [
                "too many attempts on the passkey step",
                "register",
                () => serverError(RateLimitedError, "rate_limited", 429),
                CODE_STEP_MESSAGES.rateLimited,
            ],
            [
                "no network on the code check",
                "verify",
                () => new NetworkError("network_error", "Network request failed"),
                CODE_STEP_MESSAGES.network,
            ],
            [
                "no network on the passkey step",
                "register",
                () => new NetworkError("network_error", "Network request failed"),
                CODE_STEP_MESSAGES.network,
            ],
            [
                "a server error on the code check",
                "verify",
                () => serverError(ApiRequestError, "http_500", 500),
                PARITY_COPY.auth.passkeyPanel.verifyError,
            ],
            [
                "a server error on the passkey step",
                "register",
                () => serverError(ApiRequestError, "http_503", 503),
                PARITY_COPY.auth.passkeyPanel.verifyError,
            ],
            [
                "a rejected passkey",
                "register",
                () => serverError(ApiRequestError, "invalid_passkey", 422),
                CODE_STEP_MESSAGES.passkeyFailed,
            ],
            [
                "rejected passkey credentials",
                "register",
                () => serverError(UnauthorizedError, "invalid_credentials", 401),
                CODE_STEP_MESSAGES.passkeyFailed,
            ],
            [
                "an unidentified native error on the passkey step",
                "register",
                () => new Error("native library detail"),
                PARITY_COPY.auth.passkeyPanel.passkeyUnidentifiedMobile,
            ],
            [
                "an unidentified error on the code check",
                "verify",
                () => new Error("native library detail"),
                PARITY_COPY.auth.passkeyPanel.verifyError,
            ],
            [
                "a cancelled passkey sheet",
                "register",
                () => new NoPasskeyError(),
                PARITY_COPY.auth.passkeyPanel.passkeyDismissedMobile,
            ],
            [
                "a phone with no passkey provider",
                "register",
                () => new PasskeyProviderMissingError(),
                PARITY_COPY.auth.passkeyPanel.passkeyNoProviderAndroid,
            ],
            [
                "the onboarding safety net answering 503 on the code check",
                "verify",
                () => serverError(ApiRequestError, "onboarding_unavailable", 503),
                CODE_STEP_MESSAGES.unavailable,
            ],
            [
                "the onboarding safety net answering 503 on the passkey step",
                "register",
                () => serverError(ApiRequestError, "onboarding_unavailable", 503),
                CODE_STEP_MESSAGES.unavailable,
            ],
            [
                "too many attempts with a named wait on the code check",
                "verify",
                () => new RateLimitedError("rate_limited", rawText, undefined, 429, 600),
                PARITY_COPY.auth.passkeyPanel.attemptsWait(600),
            ],
            [
                "too many attempts with a named wait on the passkey step",
                "register",
                () => new RateLimitedError("rate_limited", rawText, undefined, 429, 3600),
                PARITY_COPY.auth.passkeyPanel.attemptsWait(3600),
            ],
        ] as const)("%s shows a readable message and keeps the code box", async (_label, step, makeError, message) => {
            const mock = step === "verify" ? smsAuth.verifyCode : passkeyAuth.register;
            (mock as jest.Mock).mockRejectedValue(makeError());
            const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);

            expect(getByText(message)).toBeTruthy();
            expect(queryByText(rawText)).toBeNull();
            expect(queryByText("Network request failed")).toBeNull();
            expect(queryByText("native library detail")).toBeNull();
            expect(getByTestId("auth-code-field")).toBeTruthy();
        });

        test.each([
            ["android", PARITY_COPY.auth.passkeyPanel.passkeyCreateUnsupportedAndroid],
            ["ios", PARITY_COPY.auth.passkeyPanel.passkeyCreateUnsupportedIos],
        ] as const)(
            "a %s phone that cannot create a passkey is told to update the system and keeps the held token",
            async (os, message) => {
                const restore = jest.replaceProperty(Platform, "OS", os).restore;
                try {
                    (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(new PasskeyCreateUnsupportedError());
                    const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);
                    await reachCodeBox(getByTestId);

                    await pressConfirmCode(getByTestId);

                    expect(getByText(message)).toBeTruthy();
                    expect(queryByText(PARITY_COPY.auth.passkeyPanel.passkeyNoProviderAndroid)).toBeNull();
                    expect(getByTestId("auth-code-field")).toBeTruthy();
                    expect(mockNavigate).not.toHaveBeenCalled();

                    await pressConfirmCode(getByTestId);
                    expect(smsAuth.verifyCode).toHaveBeenCalledTimes(1);
                    expect(passkeyAuth.register).toHaveBeenCalledTimes(2);
                } finally {
                    restore();
                }
            },
        );

        test("an unidentified passkey failure names the screen lock and software fix, keeps the held token and the code box", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(
                Object.assign(new Error("Native error"), { error: "UnknownError" }),
            );
            const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);

            expect(getByText(PARITY_COPY.auth.passkeyPanel.passkeyUnidentifiedMobile)).toBeTruthy();
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.verifyError)).toBeNull();
            expect(getByTestId("auth-code-field")).toBeTruthy();
            expect(mockNavigate).not.toHaveBeenCalled();

            await pressConfirmCode(getByTestId);
            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(1);
            expect(passkeyAuth.register).toHaveBeenCalledTimes(2);
        });

        test("a phone with no passkey provider keeps the held token and never reaches the device help screen", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(new PasskeyProviderMissingError());
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);
            await pressConfirmCode(getByTestId);

            expect(mockNavigate).not.toHaveBeenCalled();
            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(1);
            expect(passkeyAuth.register).toHaveBeenCalledTimes(2);
        });

        test("a rejected passkey keeps the held token, so the retry skips the code check", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(
                serverError(ApiRequestError, "invalid_passkey", 422),
            );
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);
            await pressConfirmCode(getByTestId);

            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(1);
            expect(passkeyAuth.register).toHaveBeenCalledTimes(2);
        });

        test("an expired token returns to the phone form and asks for a new code", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValue(
                serverError(UnauthorizedError, "invalid_sms_token", 401),
            );
            const { getByTestId, getByText, queryByTestId, queryByText } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);

            expect(getByText(CODE_STEP_MESSAGES.expiredToken)).toBeTruthy();
            expect(queryByText(rawText)).toBeNull();
            expect(queryByTestId("auth-code-field")).toBeNull();
            expect(getByText(PARITY_COPY.auth.passkeyPanel.continuePhone)).toBeTruthy();
        });

        test("an existing account returns to the phone form with the passkey sign-in button", async () => {
            (passkeyAuth.register as jest.Mock).mockRejectedValue(
                serverError(ApiRequestError, "phone_already_registered", 409),
            );
            const { getByTestId, getByText, queryByTestId, queryByText } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);

            expect(getByText(CODE_STEP_MESSAGES.alreadyRegistered)).toBeTruthy();
            expect(queryByText(rawText)).toBeNull();
            expect(queryByTestId("auth-code-field")).toBeNull();
            expect(getByTestId("auth-passkey-cta")).toBeTruthy();
        });

        // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation#A session the device cannot save]]
        test("an account whose session the device cannot save returns to the phone form and says to sign in with the passkey", async () => {
            const sessionSaveError = new SessionSaveError();
            (passkeyAuth.register as jest.Mock).mockRejectedValueOnce(sessionSaveError);
            const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);
            await reachCodeBox(getByTestId);

            await pressConfirmCode(getByTestId);

            expect(getByText(sessionSaveError.message)).toBeTruthy();
            expect(queryByTestId("auth-code-field")).toBeNull();
            expect(getByTestId("auth-passkey-cta")).toBeTruthy();

            await reachCodeBox(getByTestId);
            await pressConfirmCode(getByTestId);
            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
        });
    });

    describe("sending a new code", () => {
        const reachCodeStep = async (getByTestId: ReturnType<typeof render>["getByTestId"]) => {
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
        };

        const waitOutCooldown = () => {
            act(() => {
                jest.advanceTimersByTime(60_000);
            });
        };

        const countdownText = (queryByTestId: ReturnType<typeof render>["queryByTestId"]) =>
            queryByTestId("auth-resend-countdown", { includeHiddenElements: true })?.props.children ?? null;

        const resendDisabled = (getByTestId: ReturnType<typeof render>["getByTestId"]) =>
            Boolean(getByTestId("auth-resend-cta").props.accessibilityState?.disabled);

        beforeEach(() => {
            jest.useFakeTimers();
            (passkeyAuth.signIn as jest.Mock).mockRejectedValue(new NoPasskeyError());
            (smsAuth.requestCode as jest.Mock).mockResolvedValue(undefined);
        });

        afterEach(() => {
            jest.useRealTimers();
        });

        test("pressing Send a new code requests another code for the same phone, clears the code and confirms", async () => {
            const { getByTestId, getByText, queryByText, getByPlaceholderText } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();
            fireEvent.changeText(getByTestId("auth-code-field"), "123456");
            expect(getByPlaceholderText(PARITY_COPY.auth.passkeyPanel.codePlaceholder).props.value).toBe("123456");
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeNull();

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeTruthy());
            expect(smsAuth.requestCode).toHaveBeenCalledTimes(2);
            expect(smsAuth.requestCode).toHaveBeenLastCalledWith("4105550199");
            expect(getByPlaceholderText(PARITY_COPY.auth.passkeyPanel.codePlaceholder).props.value).toBe("");
        });

        test("a new code drops the held token, so Confirm checks the new code instead of sending the old token", async () => {
            (smsAuth.verifyCode as jest.Mock)
                .mockResolvedValueOnce({ sms_verified_token: "tok-1", expires_at: "2099" })
                .mockResolvedValueOnce({ sms_verified_token: "tok-2", expires_at: "2099" });
            (passkeyAuth.register as jest.Mock)
                .mockRejectedValueOnce(new NoPasskeyError())
                .mockResolvedValueOnce(undefined);
            const { getByTestId, getByText } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();
            fireEvent.changeText(getByTestId("auth-code-field"), "123456");
            pressSubmit(getByTestId);
            await waitFor(() => expect(passkeyAuth.register).toHaveBeenCalledTimes(1));
            await waitFor(() => expect(resendDisabled(getByTestId)).toBe(false));

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));
            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeTruthy());
            fireEvent.changeText(getByTestId("auth-code-field"), "654321");
            pressSubmit(getByTestId);

            await waitFor(() => expect(passkeyAuth.register).toHaveBeenCalledTimes(2));
            expect(smsAuth.verifyCode).toHaveBeenCalledTimes(2);
            expect(smsAuth.verifyCode).toHaveBeenLastCalledWith("4105550199", "654321");
            expect(passkeyAuth.register).toHaveBeenLastCalledWith("4105550199", "tok-2");
        });

        test("pressing it twice, a cooldown apart, requests two more codes", async () => {
            const { getByTestId, getByText } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));
            await waitFor(() => expect(smsAuth.requestCode).toHaveBeenCalledTimes(2));
            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeTruthy());
            waitOutCooldown();
            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));

            await waitFor(() => expect(smsAuth.requestCode).toHaveBeenCalledTimes(3));
        });

        test("a refused resend shows the request-code error and keeps the code step open", async () => {
            const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();
            (smsAuth.requestCode as jest.Mock).mockRejectedValueOnce(new Error("rate limited"));

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.requestCodeError)).toBeTruthy());
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeNull();
            expect(getByTestId("auth-code-field")).toBeTruthy();
            expect(getByTestId("auth-submit-cta").props.accessibilityState?.disabled).toBeFalsy();
        });

        test("the button is not offered before the code step", () => {
            const { queryByText } = wrap(<AuthScreen />);

            expect(queryByText(PARITY_COPY.auth.passkeyPanel.resendCode)).toBeNull();
        });

        // @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]
        test("counts down from one minute after the first code is sent and enables the button when it ends", async () => {
            const { getByTestId, queryByTestId } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);

            expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("1:00"));
            expect(resendDisabled(getByTestId)).toBe(true);
            fireEvent.press(getByTestId("auth-resend-cta"));
            expect(smsAuth.requestCode).toHaveBeenCalledTimes(1);

            act(() => {
                jest.advanceTimersByTime(18_000);
            });
            expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("0:42"));
            expect(resendDisabled(getByTestId)).toBe(true);
            expect(getByTestId("auth-submit-cta").props.accessibilityState?.disabled).toBeFalsy();

            act(() => {
                jest.advanceTimersByTime(42_000);
            });
            expect(countdownText(queryByTestId)).toBeNull();
            expect(resendDisabled(getByTestId)).toBe(false);
        });

        test("restarts the countdown after a new code is sent", async () => {
            const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.codeResent)).toBeTruthy());
            expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("1:00"));
            expect(resendDisabled(getByTestId)).toBe(true);
        });

        test("counts down the wait the server names when it refuses a new code", async () => {
            const { getByTestId, getByText, queryByTestId, queryByText } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            waitOutCooldown();
            (smsAuth.requestCode as jest.Mock).mockRejectedValueOnce(
                new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 307),
            );

            fireEvent.press(getByText(PARITY_COPY.auth.passkeyPanel.resendCode));

            await waitFor(() =>
                expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("5:07")),
            );
            expect(resendDisabled(getByTestId)).toBe(true);
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.requestCodeError)).toBeNull();
            expect(getByTestId("auth-submit-cta").props.accessibilityState?.disabled).toBeFalsy();
        });

        test("says how long to wait when the first code is refused for longer than a minute", async () => {
            (smsAuth.requestCode as jest.Mock).mockRejectedValueOnce(
                new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 307),
            );
            const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.resendCodeWait(307))).toBeTruthy());
            expect(queryByTestId("auth-code-field")).toBeNull();
        });

        test("opens the code step with the server's wait when this screen already sent a code to the same phone", async () => {
            (smsAuth.requestCode as jest.Mock)
                .mockResolvedValueOnce(undefined)
                .mockRejectedValueOnce(new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 42));
            const { getByTestId, queryByTestId, queryByText } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
            fireEvent.press(getByTestId("auth-secondary-cta"));
            await waitFor(() => expect(queryByTestId("auth-code-field")).toBeNull());

            pressSubmit(getByTestId);

            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
            expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("0:42"));
            expect(resendDisabled(getByTestId)).toBe(true);
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.requestCodeError)).toBeNull();
        });

        test("opens the code step with the daily wait when this screen already sent a code to the same phone", async () => {
            (smsAuth.requestCode as jest.Mock)
                .mockResolvedValueOnce(undefined)
                .mockRejectedValueOnce(
                    new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 71_400),
                );
            const { getByTestId, queryByTestId, queryByText } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
            fireEvent.press(getByTestId("auth-secondary-cta"));
            await waitFor(() => expect(queryByTestId("auth-code-field")).toBeNull());

            pressSubmit(getByTestId);

            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
            expect(countdownText(queryByTestId)).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeIn("19:50:00"));
            expect(resendDisabled(getByTestId)).toBe(true);
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.requestCodeError)).toBeNull();
        });

        test("stays on the phone step and names the wait when no code was sent from this screen", async () => {
            (smsAuth.requestCode as jest.Mock).mockRejectedValueOnce(
                new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 42),
            );
            const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.resendCodeWait(42))).toBeTruthy());
            expect(queryByTestId("auth-code-field")).toBeNull();
        });

        test("stays on the phone step when the earlier code went to a different phone", async () => {
            (smsAuth.requestCode as jest.Mock)
                .mockResolvedValueOnce(undefined)
                .mockRejectedValueOnce(new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 42));
            const { getByTestId, getByText, queryByTestId } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);
            await waitFor(() => expect(getByTestId("auth-code-field")).toBeTruthy());
            fireEvent.press(getByTestId("auth-secondary-cta"));
            await waitFor(() => expect(queryByTestId("auth-code-field")).toBeNull());

            typePhone(getByTestId, "4105550123");
            pressSubmit(getByTestId);

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.resendCodeWait(42))).toBeTruthy());
            expect(queryByTestId("auth-code-field")).toBeNull();
        });

        test("shows the server's sentence when the first code is refused for an invalid phone", async () => {
            (smsAuth.requestCode as jest.Mock).mockRejectedValueOnce(
                new ApiRequestError("invalid_phone", "Enter a valid US phone number.", undefined, 422),
            );
            const { getByTestId, getByText, queryByTestId, queryByText } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);

            await waitFor(() => expect(getByText("Enter a valid US phone number.")).toBeTruthy());
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.requestCodeError)).toBeNull();
            expect(queryByTestId("auth-code-field")).toBeNull();
        });

        test("says how long to wait when phone sign-in itself is rate limited", async () => {
            (passkeyAuth.signIn as jest.Mock).mockRejectedValue(
                new RateLimitedError("rate_limited", "Too many attempts.", undefined, 429, 90),
            );
            const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);
            typePhone(getByTestId);
            pressSubmit(getByTestId);

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.signInWait(90))).toBeTruthy());
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.resendCodeWait(90))).toBeNull();
            expect(queryByText(PARITY_COPY.auth.passkeyPanel.signInError)).toBeNull();
            expect(smsAuth.requestCode).not.toHaveBeenCalled();
        });

        test("hides the ticking clock from screen readers and announces the wait once", async () => {
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);
            const region = () => getByTestId("auth-resend-wait");

            expect(region().props.accessibilityLiveRegion).toBe("polite");
            expect(region().props.accessibilityLabel).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeWait(60));
            expect(
                getByTestId("auth-resend-countdown", { includeHiddenElements: true }).props.importantForAccessibility,
            ).toBe("no");
            expect(getByTestId("auth-resend-cta").props.accessibilityLabel).toBe(
                PARITY_COPY.auth.passkeyPanel.resendCode,
            );

            act(() => {
                jest.advanceTimersByTime(5_000);
            });
            expect(region().props.accessibilityLabel).toBe(PARITY_COPY.auth.passkeyPanel.resendCodeWait(60));
        });

        test("keeps a 44pt touch target and readable label while waiting", async () => {
            const { getByTestId } = wrap(<AuthScreen />);
            await reachCodeStep(getByTestId);

            const flat = StyleSheet.flatten(getByTestId("auth-resend-cta").props.style);
            expect(flat.minHeight).toBeGreaterThanOrEqual(44);
            expect(flat.opacity).toBe(0.75);
        });
    });

    test.each(["phone", "discoverable"] as const)(
        "shows retry guidance for unexpected %s sign-in errors",
        async (flow) => {
            const internalMessage = "BadConfiguration: internal relying-party host details";
            const signIn = flow === "phone" ? passkeyAuth.signIn : passkeyAuth.signInDiscoverable;
            (signIn as jest.Mock).mockRejectedValue(new Error(internalMessage));
            const { getByTestId, getByText, queryByText } = wrap(<AuthScreen />);

            if (flow === "phone") {
                typePhone(getByTestId);
                pressSubmit(getByTestId);
            } else {
                fireEvent.press(getByTestId("auth-passkey-cta"));
            }

            await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.signInError)).toBeTruthy());
            expect(queryByText(internalMessage)).toBeNull();
            expect(smsAuth.requestCode).not.toHaveBeenCalled();
            expect(mockNavigate).not.toHaveBeenCalled();
        },
    );

    test("keeps discoverable cancellation on the phone form without an error or SMS", async () => {
        (passkeyAuth.signInDiscoverable as jest.Mock).mockRejectedValue(new NoPasskeyError());
        const { getByTestId, queryByTestId, queryByText } = wrap(<AuthScreen />);
        fireEvent.press(getByTestId("auth-passkey-cta"));

        await waitFor(() => expect(passkeyAuth.signInDiscoverable).toHaveBeenCalled());
        await waitFor(() => expect(queryByTestId("auth-loading-panel")).toBeNull(), { timeout: 3000 });
        expect(getByTestId("auth-phone-field")).toBeTruthy();
        expect(queryByText(PARITY_COPY.auth.passkeyPanel.signInError)).toBeNull();
        expect(queryByText("no_credential")).toBeNull();
        expect(smsAuth.requestCode).not.toHaveBeenCalled();
        expect(mockNavigate).not.toHaveBeenCalled();
    });

    test("routes unsupported discoverable sign-in to the device help screen", async () => {
        (passkeyAuth.signInDiscoverable as jest.Mock).mockRejectedValue(new PasskeyUnsupportedError());
        const { getByTestId } = wrap(<AuthScreen />);
        fireEvent.press(getByTestId("auth-passkey-cta"));

        await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith("DeviceUnsupported"));
        expect(smsAuth.requestCode).not.toHaveBeenCalled();
    });

    test("validation: rejects submit when phone is not 10 digits", async () => {
        const { getByTestId, getByText } = wrap(<AuthScreen />);

        fireEvent.changeText(getByTestId("auth-phone-field"), "123");
        pressSubmit(getByTestId);

        expect(passkeyAuth.signIn).not.toHaveBeenCalled();

        await waitFor(() => expect(getByText(PARITY_COPY.auth.passkeyPanel.validationPhone)).toBeTruthy());
    });

    test("Preview Sway invokes Linking.openURL with the canonical web URL (Codex Concern 1)", async () => {
        // Watch Linking.openURL, the same way UpdateBanner.test.tsx does.
        const openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);

        const { getByTestId } = wrap(<AuthScreen />);

        // At the start, before the code box appears, the second button reads "Preview Sway".
        fireEvent.press(getByTestId("auth-secondary-cta"));

        expect(openURLSpy).toHaveBeenCalledWith(PARITY_COPY.auth.passkeyPanel.previewSwayUrl);
        // A second, looser check: that address is on the sway.vote domain.
        expect(openURLSpy).toHaveBeenCalledWith(expect.stringContaining("sway.vote/bill_of_the_month"));

        // It must NOT navigate to "BillOfTheMonth". That screen sits in a
        // different stack, and for a signed-out user the tabs holding it are
        // never mounted, so the app would fall over.
        expect(mockNavigate).not.toHaveBeenCalledWith("BillOfTheMonth");

        openURLSpy.mockRestore();
    });
});

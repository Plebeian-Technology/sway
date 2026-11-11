// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile authentication screen]]

import React from "react";
import { Linking } from "react-native";
import { render, fireEvent, waitFor } from "@testing-library/react-native";

import { passkeyAuth, PasskeyUnsupportedError, NoPasskeyError } from "../../src/auth/passkeyAuth";
import { smsAuth } from "../../src/auth/smsAuth";
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
    class NoPasskeyError extends Error {
        constructor() {
            super("no_credential");
            this.name = "NoPasskeyError";
        }
    }
    return {
        passkeyAuth: { signIn: jest.fn(), signInDiscoverable: jest.fn(), register: jest.fn() },
        PasskeyUnsupportedError,
        NoPasskeyError,
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
    test("a cancelled passkey enrolment leaves the code box up with no error text", async () => {
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

// @lat: [[mobile-jest-first-pass-test-notes#PasskeyManagementScreen.test.tsx]]

const mockGet = jest.fn();
const mockDelete = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

const mockRequestCode = jest.fn();
const mockVerifyCode = jest.fn();
jest.mock("../../src/auth/smsAuth", () => ({
    smsAuth: {
        requestCode: (...args: unknown[]) => mockRequestCode(...args),
        verifyCode: (...args: unknown[]) => mockVerifyCode(...args),
    },
}));

const mockAddPasskey = jest.fn();
jest.mock("../../src/auth/passkeyAuth", () => {
    const actual = jest.requireActual("../../src/auth/passkeyAuth");
    return {
        ...actual,
        passkeyAuth: {
            ...actual.passkeyAuth,
            addPasskey: (...args: unknown[]) => mockAddPasskey(...args),
        },
    };
});

import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import PasskeyManagementScreen from "../../src/screens/PasskeyManagementScreen";
import { NoPasskeyError } from "../../src/auth/passkeyAuth";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("PasskeyManagementScreen (Phase 37 Plan 05; add a passkey)", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockDelete.mockReset();
        mockRequestCode.mockReset();
        mockVerifyCode.mockReset();
        mockAddPasskey.mockReset();
    });

    test("renders loading indicator on mount", async () => {
        // a promise that never finishes, so the screen stays in its loading state
        mockGet.mockImplementation(() => new Promise(() => {}));
        const tree = wrap(<PasskeyManagementScreen />);
        expect(screen.getByLabelText("Loading passkeys")).toBeTruthy();
        expect(tree.toJSON()).toMatchSnapshot();
    });

    test("renders loaded state with two rows (one with last_used_at, one without)", async () => {
        mockGet.mockResolvedValueOnce([
            {
                id: 1,
                label: "iPhone 15",
                created_at: "2026-01-15T00:00:00Z",
                last_used_at: "2026-04-20T00:00:00Z",
                device: "iCloud Keychain (Managed)",
            },
            {
                id: 2,
                label: "MacBook Air",
                created_at: "2026-02-01T00:00:00Z",
                last_used_at: null,
                device: null,
            },
        ]);
        const tree = wrap(<PasskeyManagementScreen />);
        await waitFor(() => {
            expect(screen.getByTestId("passkey-row-1")).toBeTruthy();
        });
        expect(screen.getByTestId("passkey-row-2")).toBeTruthy();
        expect(screen.getByText("iPhone 15")).toBeTruthy();
        expect(screen.getByText("MacBook Air")).toBeTruthy();
        expect(screen.getByText("Never used")).toBeTruthy();
        // The device line shows whether or not we recognize the authenticator's own id,
        // the AAGUID a passkey device reports.
        expect(screen.getByText(/Device: iCloud Keychain \(Managed\)/)).toBeTruthy();
        expect(screen.getByText(/Device: Unknown device/)).toBeTruthy();

        expect(screen.queryByText(/Remove/i)).toBeNull();
        expect(screen.queryByTestId(/btn-remove-passkey/)).toBeNull();
        expect(screen.queryByTestId("sheet-revoke-passkey")).toBeNull();
        expect(screen.queryByTestId("sheet-remove-passkey")).toBeNull();
        expect(mockDelete).not.toHaveBeenCalled();

        expect(tree.toJSON()).toMatchSnapshot();
    });

    test("renders loaded state when server returns object with passkeys property", async () => {
        mockGet.mockResolvedValueOnce({
            passkeys: [
                {
                    id: 3,
                    label: "Pixel 9",
                    created_at: "2026-03-01T00:00:00Z",
                    last_used_at: "2026-05-01T00:00:00Z",
                    device: "Android KeyStore",
                },
            ],
        });
        wrap(<PasskeyManagementScreen />);
        await waitFor(() => {
            expect(screen.getByTestId("passkey-row-3")).toBeTruthy();
        });
        expect(screen.getByText("Pixel 9")).toBeTruthy();
        expect(screen.getByText(/Device: Android KeyStore/)).toBeTruthy();
        expect(mockGet).toHaveBeenCalledWith("/users/passkeys");
    });

    test("renders empty state when API returns no passkeys", async () => {
        mockGet.mockResolvedValueOnce([]);
        const tree = wrap(<PasskeyManagementScreen />);
        await waitFor(() => {
            expect(screen.getByText("No passkeys on this account.")).toBeTruthy();
        });
        expect(screen.queryByTestId(/^passkey-row-/)).toBeNull();
        expect(screen.queryByText(/Remove/i)).toBeNull();
        expect(tree.toJSON()).toMatchSnapshot();
    });

    test("renders error state when API rejects", async () => {
        mockGet.mockRejectedValueOnce(new Error("boom"));
        const tree = wrap(<PasskeyManagementScreen />);
        await waitFor(() => {
            expect(screen.getByTestId("passkey-error")).toBeTruthy();
        });
        // The error's own message reaches the screen, which is how apiClient reports failures
        expect(screen.getByText("boom")).toBeTruthy();
        expect(screen.queryByText(/Remove/i)).toBeNull();
        expect(tree.toJSON()).toMatchSnapshot();
    });

    test("falls back to PARITY_COPY.passkey.errorLoad when error has no message", async () => {
        mockGet.mockRejectedValueOnce("string-not-error");
        wrap(<PasskeyManagementScreen />);
        await waitFor(() => {
            expect(screen.getByTestId("passkey-error")).toBeTruthy();
        });
        expect(screen.getByText("Could not load passkeys.")).toBeTruthy();
    });

    test("validates non-empty code, keeps code inputs visible while confirming, and returns to phone step with friendly message if addPasskey fails after code verification", async () => {
        mockGet.mockResolvedValue([]);
        mockRequestCode.mockResolvedValue({ sent: true });
        wrap(<PasskeyManagementScreen />);
        await waitFor(() => expect(screen.getByTestId("add-passkey-start")).toBeTruthy());

        fireEvent.press(screen.getByTestId("add-passkey-start"));
        fireEvent.changeText(screen.getByTestId("add-passkey-phone"), "4105550199");
        await act(async () => {
            fireEvent.press(screen.getByTestId("add-passkey-confirm"));
        });
        await waitFor(() => expect(screen.getByTestId("add-passkey-code")).toBeTruthy());

        // Blank code validation before verifyCode
        fireEvent.changeText(screen.getByTestId("add-passkey-code"), "   ");
        fireEvent.press(screen.getByTestId("add-passkey-confirm"));
        expect(mockVerifyCode).not.toHaveBeenCalled();
        expect(screen.getByTestId("add-passkey-error")).toBeTruthy();

        // Hold verifyCode in-flight to verify code/name inputs remain visible during "working"
        let resolveVerify!: (v: { sms_verified_token: string }) => void;
        mockVerifyCode.mockImplementationOnce(
            () =>
                new Promise((resolve) => {
                    resolveVerify = resolve;
                }),
        );
        mockAddPasskey.mockRejectedValueOnce(new NoPasskeyError());

        fireEvent.changeText(screen.getByTestId("add-passkey-code"), "123456");
        fireEvent.press(screen.getByTestId("add-passkey-confirm"));
        expect(screen.getByTestId("add-passkey-code")).toBeTruthy();
        expect(screen.getByTestId("add-passkey-name")).toBeTruthy();
        expect(screen.queryByTestId("add-passkey-phone")).toBeNull();

        await act(async () => {
            resolveVerify({ sms_verified_token: "tok_sms" });
        });

        await waitFor(() => expect(screen.getByTestId("add-passkey-phone")).toBeTruthy());
        const errText = screen.getByTestId("add-passkey-error").props.children;
        expect(String(errText)).not.toContain("no_credential");
        expect(String(errText)).toMatch(/request a new code/i);
    });

    // Let any leftover background work settle, so React Native stops warning about act().
    afterEach(async () => {
        await act(async () => {
            await Promise.resolve();
        });
    });
});

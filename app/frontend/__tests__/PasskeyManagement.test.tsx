import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Keep the page away from the real network calls in useAddPasskey, which go
// through Inertia's useHttp. Setting `step` by hand lets the tests check both
// the resting screen and the waiting-for-the-SMS-code screen.
const addPasskeyMock = vi.hoisted(() => ({
    step: "idle" as "idle" | "awaiting_code" | "working",
    begin: vi.fn<() => Promise<void>>(),
    submit: vi.fn<(code: string, label: string) => Promise<void>>(),
    cancel: vi.fn<() => void>(),
}));

vi.mock("app/frontend/hooks/authentication/useAddPasskey", () => ({
    useAddPasskey: () => addPasskeyMock,
}));

vi.mock("app/frontend/hooks/authentication/useRemovePasskey", () => ({
    useRemovePasskey: () => ({
        step: "idle",
        target: null,
        begin: vi.fn<() => Promise<void>>(),
        submit: vi.fn<(code: string) => Promise<void>>(),
        cancel: vi.fn<() => void>(),
    }),
}));

import PasskeyManagement from "app/frontend/pages/PasskeyManagement";

describe("pages/PasskeyManagement (add a passkey)", () => {
    beforeEach(() => {
        addPasskeyMock.step = "idle";
        addPasskeyMock.begin.mockReset().mockResolvedValue(undefined);
        addPasskeyMock.submit.mockReset().mockResolvedValue(undefined);
        addPasskeyMock.cancel.mockReset();
    });

    afterEach(() => {
        cleanup();
    });

    it("renders the page heading and lead copy from PARITY_COPY.passkey", () => {
        render(<PasskeyManagement passkeys={[]} />);
        expect(screen.getByRole("heading", { name: /Passkey Management/i })).toBeTruthy();
        expect(screen.getByText(/Passkeys let you sign in without typing a code\./i)).toBeTruthy();
    });

    it("renders one li per passkey with the expected testID and label", () => {
        render(
            <PasskeyManagement
                passkeys={[
                    {
                        id: 1,
                        label: "iPhone 15",
                        created_at: "2026-01-15T00:00:00Z",
                        last_used_at: "2026-04-20T00:00:00Z",
                        device: "iCloud Keychain (Managed)",
                    },
                    {
                        id: 2,
                        label: null,
                        created_at: "2026-02-01T00:00:00Z",
                        last_used_at: null,
                        device: null,
                    },
                ]}
            />,
        );
        expect(screen.getByTestId("passkey-row-1")).toBeTruthy();
        expect(screen.getByTestId("passkey-row-2")).toBeTruthy();
        expect(screen.getByText("iPhone 15")).toBeTruthy();
        // A passkey with no label of its own is shown as "Passkey".
        expect(screen.getByText("Passkey")).toBeTruthy();
    });

    it('renders "Last used {date}" and "Never used" branches correctly', () => {
        render(
            <PasskeyManagement
                passkeys={[
                    {
                        id: 1,
                        label: "Used",
                        created_at: "2026-01-15T00:00:00Z",
                        last_used_at: "2026-04-20T00:00:00Z",
                        device: "iCloud Keychain (Managed)",
                    },
                    {
                        id: 2,
                        label: "Fresh",
                        created_at: "2026-02-01T00:00:00Z",
                        last_used_at: null,
                        device: null,
                    },
                ]}
            />,
        );
        expect(screen.getByText(/Last used /)).toBeTruthy();
        expect(screen.getByText("Never used")).toBeTruthy();
    });

    it("renders the empty copy when passkeys is []", () => {
        render(<PasskeyManagement passkeys={[]} />);
        expect(screen.getByTestId("passkey-empty")).toBeTruthy();
        expect(screen.getByText("No passkeys on this account.")).toBeTruthy();
    });

    it("renders Device: <name> for known AAGUID and Device: Unknown device for null", () => {
        render(
            <PasskeyManagement
                passkeys={[
                    {
                        id: 1,
                        label: "iPhone 15",
                        created_at: "2026-01-15T00:00:00Z",
                        last_used_at: null,
                        device: "iCloud Keychain (Managed)",
                    },
                    {
                        id: 2,
                        label: "MacBook Air",
                        created_at: "2026-02-01T00:00:00Z",
                        last_used_at: null,
                        device: null,
                    },
                ]}
            />,
        );
        expect(screen.getByText(/Device: iCloud Keychain \(Managed\)/)).toBeTruthy();
        expect(screen.getByText(/Device: Unknown device/)).toBeTruthy();
    });

    // This page used to be look-but-don't-touch on purpose. That limit is
    // lifted: a signed-in user can choose to add a passkey their device can
    // find on its own, after confirming a code sent by SMS.
    it("shows the add-a-passkey affordance in the idle state and starts the flow on click", () => {
        render(<PasskeyManagement passkeys={[]} />);
        const start = screen.getByTestId("add-passkey-start");
        expect(start).toBeTruthy();
        fireEvent.click(start);
        expect(addPasskeyMock.begin).toHaveBeenCalledTimes(1);
    });

    it("shows the device-name + code inputs while awaiting the SMS code, and submits them", () => {
        addPasskeyMock.step = "awaiting_code";
        render(<PasskeyManagement passkeys={[]} />);

        fireEvent.change(screen.getByTestId("add-passkey-name"), { target: { value: "My laptop" } });
        fireEvent.change(screen.getByTestId("add-passkey-code"), { target: { value: "123456" } });
        fireEvent.click(screen.getByTestId("add-passkey-confirm"));

        expect(addPasskeyMock.submit).toHaveBeenCalledWith("123456", "My laptop");
    });
});

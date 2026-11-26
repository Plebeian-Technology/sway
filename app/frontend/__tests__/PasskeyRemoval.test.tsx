// @lat: [[passkey-management-page-overview#Removing a passkey#The web remove flow]]

import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const inertia = vi.hoisted(() => ({
    http: {
        transform: vi.fn<(fn: () => unknown) => void>(),
        post: vi.fn<(url: string) => Promise<unknown>>(),
        delete: vi.fn<(url: string) => Promise<unknown>>(),
    },
    router: { reload: vi.fn<(options?: unknown) => void>() },
}));

vi.mock("@inertiajs/react", () => ({
    useHttp: () => inertia.http,
    router: inertia.router,
}));

const notified = vi.hoisted(() => vi.fn<(options: { level: string; title: string }) => void>());

vi.mock("app/frontend/sway_utils", async (importActual) => ({
    ...(await importActual<typeof import("app/frontend/sway_utils")>()),
    notify: notified,
}));

import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import PasskeyManagement from "app/frontend/pages/PasskeyManagement";

const PASSKEYS = [
    { id: 1, label: "Old phone", created_at: "2026-01-15T00:00:00Z", last_used_at: null, device: null },
    { id: 2, label: "Laptop", created_at: "2026-02-01T00:00:00Z", last_used_at: null, device: null },
];

type Passkeys = typeof PASSKEYS;

const renderPage = (passkeys: Passkeys) =>
    render(
        <ConfirmProvider>
            <PasskeyManagement passkeys={passkeys} />
        </ConfirmProvider>,
    );

const startRemoval = async (rowId: number) => {
    fireEvent.click(within(screen.getByTestId(`passkey-row-${rowId}`)).getByRole("button", { name: "Remove" }));
    fireEvent.change(await screen.findByTestId("remove-passkey-code"), { target: { value: "123456" } });
    fireEvent.click(screen.getByTestId("remove-passkey-confirm-code"));
};

describe("pages/PasskeyManagement (remove a passkey)", () => {
    beforeEach(() => {
        inertia.http.transform.mockReset();
        inertia.http.post.mockReset().mockResolvedValue({ success: true });
        inertia.http.delete.mockReset().mockResolvedValue({ success: true });
        inertia.router.reload.mockReset();
        notified.mockReset();
    });

    afterEach(() => {
        cleanup();
    });

    it("shows Remove on every row when the user has more than one passkey", () => {
        renderPage(PASSKEYS);

        for (const passkey of PASSKEYS) {
            const row = screen.getByTestId(`passkey-row-${passkey.id}`);
            expect(within(row).getByRole("button", { name: "Remove" })).toBeTruthy();
        }
    });

    it("shows no Remove button and says the last passkey cannot be removed when only one is left", () => {
        renderPage([PASSKEYS[0]]);

        expect(screen.queryByRole("button", { name: "Remove" })).toBeNull();
        expect(screen.getByText("You must keep at least one passkey to sign in.")).toBeTruthy();
    });

    it("texts a code, confirms in a dialog naming the passkey, deletes it and refreshes the list", async () => {
        const { rerender } = renderPage(PASSKEYS);

        await startRemoval(1);

        const dialog = await screen.findByRole("dialog", { name: "Remove this passkey?" });
        expect(dialog.textContent).toContain("Old phone");
        expect(inertia.http.post.mock.calls.map(([url]) => url)).toEqual([
            "/users/passkeys/verify_phone",
            "/users/passkeys/confirm_phone",
        ]);
        expect(inertia.http.delete).not.toHaveBeenCalled();

        fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

        await waitFor(() => expect(inertia.router.reload).toHaveBeenCalledWith({ only: ["passkeys"] }));
        expect(inertia.http.delete).toHaveBeenCalledWith("/users/passkeys/1");

        rerender(
            <ConfirmProvider>
                <PasskeyManagement passkeys={[PASSKEYS[1]]} />
            </ConfirmProvider>,
        );
        expect(screen.queryByTestId("passkey-row-1")).toBeNull();
        expect(screen.getByTestId("passkey-row-2")).toBeTruthy();
    });

    it("sends nothing when the confirmation dialog is cancelled", async () => {
        renderPage(PASSKEYS);

        await startRemoval(1);
        const dialog = await screen.findByRole("dialog", { name: "Remove this passkey?" });
        fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

        await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
        expect(inertia.http.delete).not.toHaveBeenCalled();
    });

    it("shows the server's refusal message and keeps the list", async () => {
        inertia.http.delete.mockResolvedValue({ success: false, message: "Your last passkey cannot be removed." });
        renderPage(PASSKEYS);

        await startRemoval(1);
        const dialog = await screen.findByRole("dialog", { name: "Remove this passkey?" });
        fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

        await waitFor(() =>
            expect(notified).toHaveBeenCalledWith({ level: "error", title: "Your last passkey cannot be removed." }),
        );
        expect(inertia.router.reload).not.toHaveBeenCalled();
    });

    it("shows a message instead of crashing when the delete request fails", async () => {
        inertia.http.delete.mockRejectedValue(new Error("404"));
        renderPage(PASSKEYS);

        await startRemoval(1);
        const dialog = await screen.findByRole("dialog", { name: "Remove this passkey?" });
        fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

        await waitFor(() =>
            expect(notified).toHaveBeenCalledWith({
                level: "error",
                title: "Couldn't remove the passkey. Please try again.",
            }),
        );
        expect(screen.getByTestId("passkey-row-1")).toBeTruthy();
    });

    it("shows the throttle copy, not the remove error, when the code text is throttled, and returns to idle", async () => {
        inertia.http.post.mockRejectedValue({ response: { status: 429, headers: { "retry-after": "90" } } });
        renderPage(PASSKEYS);

        fireEvent.click(within(screen.getByTestId("passkey-row-1")).getByRole("button", { name: "Remove" }));

        await waitFor(() =>
            expect(notified).toHaveBeenCalledWith({
                level: "error",
                title: "Too many verification attempts. Please wait 2 minutes before trying again.",
            }),
        );
        expect(notified).toHaveBeenCalledTimes(1);
        expect(screen.queryByTestId("remove-passkey-code")).toBeNull();
        expect(within(screen.getByTestId("passkey-row-1")).getByRole("button", { name: "Remove" })).toBeTruthy();
    });

    it("stops at the code step when the code is wrong", async () => {
        inertia.http.post.mockImplementation(async (url) =>
            url.endsWith("confirm_phone") ? { success: false } : { success: true },
        );
        renderPage(PASSKEYS);

        await startRemoval(1);

        await waitFor(() =>
            expect(notified).toHaveBeenCalledWith({
                level: "error",
                title: "That code didn't work. Please try again.",
            }),
        );
        expect(screen.queryByRole("dialog")).toBeNull();
        expect(inertia.http.delete).not.toHaveBeenCalled();
    });
});

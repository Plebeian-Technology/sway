import { cleanup, fireEvent, render as rtlRender, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const inertia = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    router: {
        delete: vi.fn<(url: string, options?: unknown) => void>(),
        post: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
    },
}));

const identity = vi.hoisted(() => ({ clearIdentityCaches: vi.fn<() => void>() }));

vi.mock("app/frontend/hooks/authentication/prepareIdentityChange", () => identity);

vi.mock("@inertiajs/react", () => ({
    usePage: inertia.usePage,
    router: inertia.router,
    Link: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a>,
}));

import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import Profile from "app/frontend/pages/Profile";

const render = (ui: React.ReactElement) => rtlRender(<ConfirmProvider>{ui}</ConfirmProvider>);

describe("Profile", () => {
    beforeEach(() => {
        inertia.router.delete.mockReset();
        identity.clearIdentityCaches.mockReset();
        inertia.router.post.mockReset();
        inertia.usePage.mockReturnValue({
            props: { user: { id: 7, full_name: "Ada Lovelace", phone: "4105550123" } },
        });
    });

    afterEach(() => {
        cleanup();
    });

    it("shows the signed-in user's name and phone", () => {
        render(<Profile can_manage_api_keys={false} />);

        expect(screen.getByText("Ada Lovelace")).toBeTruthy();
        expect(screen.getByText("(410) 555 - 0123")).toBeTruthy();
    });

    it.each([
        ["Address", "/users/address/edit"],
        ["Passkey Management", "/users/passkeys"],
        ["Notification Preferences", "/notifications"],
        ["My Memberships", "/users/organization_memberships"],
    ])("links %s to %s", (label, href) => {
        render(<Profile can_manage_api_keys={false} />);

        expect(screen.getByRole("link", { name: label }).getAttribute("href")).toBe(href);
    });

    it("links Notification Preferences even when the browser has no Notification API", () => {
        const original = Object.getOwnPropertyDescriptor(window, "Notification");
        // @ts-expect-error jsdom allows removing the global for this test
        delete window.Notification;
        try {
            render(<Profile can_manage_api_keys={false} />);
            expect(screen.getByRole("link", { name: "Notification Preferences" })).toBeTruthy();
        } finally {
            if (original) Object.defineProperty(window, "Notification", original);
        }
    });

    it("links API Keys for a user allowed to manage them", () => {
        render(<Profile can_manage_api_keys={true} />);

        expect(screen.getByRole("link", { name: "API Keys" }).getAttribute("href")).toBe("/api_keys");
    });

    it("shows no API Keys link to any other user", () => {
        render(<Profile can_manage_api_keys={false} />);

        expect(screen.queryByRole("link", { name: "API Keys" })).toBeNull();
    });

    describe("Delete Account", () => {
        it("asks for confirmation, saying what is deleted, before deleting anything", () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Delete Account" }));

            const dialog = screen.getByRole("dialog", { name: "Delete account" });
            expect(dialog.textContent).toContain(
                "This permanently removes your votes, profile, and history. This cannot be undone.",
            );
            expect(inertia.router.delete).not.toHaveBeenCalled();
        });

        it("does nothing when the confirmation is cancelled", async () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Delete Account" }));
            fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));

            await vi.waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
            expect(inertia.router.delete).not.toHaveBeenCalled();
        });

        it("deletes the signed-in user's own account once confirmed", async () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Delete Account" }));
            const dialog = screen.getByRole("dialog", { name: "Delete account" });
            fireEvent.click(within(dialog).getByRole("button", { name: "Delete Account" }));

            await vi.waitFor(() => expect(inertia.router.delete).toHaveBeenCalledTimes(1));
            expect(inertia.router.delete.mock.calls[0][0]).toBe("/users/7");
        });

        const confirmAndDelete = async () => {
            render(<Profile can_manage_api_keys={false} />);
            fireEvent.click(screen.getByRole("button", { name: "Delete Account" }));
            const dialog = screen.getByRole("dialog", { name: "Delete account" });
            fireEvent.click(within(dialog).getByRole("button", { name: "Delete Account" }));
            await vi.waitFor(() => expect(inertia.router.delete).toHaveBeenCalledTimes(1));
            return inertia.router.delete.mock.calls[0][1] as { onSuccess: (page: unknown) => void };
        };

        it("clears the browser's identity caches once the account is gone", async () => {
            const { onSuccess } = await confirmAndDelete();

            onSuccess({ props: { user: null } });

            expect(identity.clearIdentityCaches).toHaveBeenCalledTimes(1);
        });

        it("keeps the identity caches when the server refuses and the same user is still signed in", async () => {
            const { onSuccess } = await confirmAndDelete();

            onSuccess({ props: { user: { id: 7 } } });

            expect(identity.clearIdentityCaches).not.toHaveBeenCalled();
        });
    });

    describe("Sign Out All Devices", () => {
        it("asks for confirmation before signing anything out", () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Sign Out All Devices" }));

            const dialog = screen.getByRole("dialog", { name: "Sign out all devices" });
            expect(dialog.textContent).toContain("You'll be signed out on every device.");
            expect(inertia.router.post).not.toHaveBeenCalled();
        });

        it("does nothing when the confirmation is cancelled", async () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Sign Out All Devices" }));
            fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));

            await vi.waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
            expect(inertia.router.post).not.toHaveBeenCalled();
        });

        it("calls the sign-out-everywhere endpoint once confirmed", async () => {
            render(<Profile can_manage_api_keys={false} />);

            fireEvent.click(screen.getByRole("button", { name: "Sign Out All Devices" }));
            const dialog = screen.getByRole("dialog", { name: "Sign out all devices" });
            fireEvent.click(within(dialog).getByRole("button", { name: "Sign Out All Devices" }));

            await vi.waitFor(() => expect(inertia.router.post).toHaveBeenCalledTimes(1));
            expect(inertia.router.post.mock.calls[0][0]).toBe("/users/sign_out_all_devices");
        });

        const confirmAndSignOut = async () => {
            render(<Profile can_manage_api_keys={false} />);
            fireEvent.click(screen.getByRole("button", { name: "Sign Out All Devices" }));
            const dialog = screen.getByRole("dialog", { name: "Sign out all devices" });
            fireEvent.click(within(dialog).getByRole("button", { name: "Sign Out All Devices" }));
            await vi.waitFor(() => expect(inertia.router.post).toHaveBeenCalledTimes(1));
            return inertia.router.post.mock.calls[0][2] as { onSuccess: (page: unknown) => void };
        };

        it("clears the browser's identity caches once the user is signed out", async () => {
            const { onSuccess } = await confirmAndSignOut();

            onSuccess({ props: { user: null } });

            expect(identity.clearIdentityCaches).toHaveBeenCalledTimes(1);
        });

        it("keeps the identity caches when the server refuses and the same user is still signed in", async () => {
            const { onSuccess } = await confirmAndSignOut();

            onSuccess({ props: { user: { id: 7 } } });

            expect(identity.clearIdentityCaches).not.toHaveBeenCalled();
        });
    });
});

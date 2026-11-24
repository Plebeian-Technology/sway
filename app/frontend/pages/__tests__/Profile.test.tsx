import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const inertia = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
}));

vi.mock("@inertiajs/react", () => ({
    usePage: inertia.usePage,
    Link: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a>,
}));

import Profile from "app/frontend/pages/Profile";

describe("Profile", () => {
    beforeEach(() => {
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
});

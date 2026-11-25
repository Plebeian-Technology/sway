// @lat: [[public-disclosure-pages#Public disclosure pages#Why the component tests are the only cover for the text]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Head: () => null,
    Link: ({ children, href, className }: { children: React.ReactNode; href: string; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

import Terms from "app/frontend/pages/public/Terms";

describe("public/Terms", () => {
    afterEach(() => {
        cleanup();
    });

    it("states Sway is free", () => {
        render(<Terms />);
        expect(screen.getByText(/Sway is free to use/)).toBeTruthy();
    });

    it("states accounts require a verified phone number", () => {
        render(<Terms />);
        expect(screen.getByText(/a mobile phone number that you verify by SMS/)).toBeTruthy();
    });

    it("states the messaging terms: frequency, rates, and opt-out", () => {
        render(<Terms />);
        expect(screen.getByText(/1-3 messages per week/)).toBeTruthy();
        expect(screen.getByText(/Msg&data rates may apply/)).toBeTruthy();
        expect(screen.getByText(/Reply STOP to cancel/)).toBeTruthy();
        expect(screen.getByText(/new Bill of the Month alerts/)).toBeTruthy();
    });

    it("says readers track organizations and that Sway records their positions", () => {
        render(<Terms />);
        expect(screen.getByText(/and track organizations and representatives you care about/)).toBeTruthy();
        expect(screen.getByText(/or for tracking organizations and representatives/)).toBeTruthy();
        expect(
            screen.getByText(/notices when Sway records a position on a bill from an organization you track/),
        ).toBeTruthy();
        expect(screen.queryByText(/follow/)).toBeNull();
    });

    it("carries no draft marker", () => {
        render(<Terms />);
        expect(screen.queryByText(/Draft/)).toBeNull();
    });

    it("links to the privacy policy", () => {
        render(<Terms />);
        const link = screen.getByRole("link", { name: "privacy policy" });
        expect(link.getAttribute("href")).toBe("/privacy");
    });
});

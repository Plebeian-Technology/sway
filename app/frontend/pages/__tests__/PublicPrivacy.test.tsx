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

import Privacy from "app/frontend/pages/public/Privacy";

describe("public/Privacy", () => {
    afterEach(() => {
        cleanup();
    });

    it("describes what data Sway collects", () => {
        render(<Privacy />);
        expect(screen.getByText("Phone number")).toBeTruthy();
        expect(screen.getByText("Address")).toBeTruthy();
        expect(screen.getByText("Votes you cast on legislation")).toBeTruthy();
    });

    it("describes sign-up telemetry using random visitor tokens", () => {
        render(<Privacy />);
        expect(screen.getByText(/random visitor token/)).toBeTruthy();
    });

    it("names the outside services that help run Sway", () => {
        render(<Privacy />);
        expect(screen.getByText(/Firebase/)).toBeTruthy();
        expect(screen.getByText(/Sentry/)).toBeTruthy();
        expect(screen.getByText(/Google Cloud Storage/)).toBeTruthy();
    });

    it("states the mandatory carrier clause: phone numbers and SMS opt-in data are never sold or shared for marketing", () => {
        render(<Privacy />);
        expect(
            screen.getByText(
                "Mobile phone numbers and SMS opt-in data are never sold, rented, or shared with third parties for marketing purposes.",
            ),
        ).toBeTruthy();
    });

    it("carries no draft marker", () => {
        render(<Privacy />);
        expect(screen.queryByText(/Draft/)).toBeNull();
    });

    it("links to the terms of service", () => {
        render(<Privacy />);
        const link = screen.getByRole("link", { name: "terms of service" });
        expect(link.getAttribute("href")).toBe("/terms");
    });

    it("links to the SMS disclosure page", () => {
        render(<Privacy />);
        const links = screen.getAllByRole("link", { name: /sms/i });
        expect(links.some((link) => link.getAttribute("href") === "/sms")).toBe(true);
    });
});

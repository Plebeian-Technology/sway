// @lat: [[public-disclosure-pages#Public disclosure pages#Why the component tests are the only cover for the text]]

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Head: () => null,
    Link: ({ children, href, className }: { children: React.ReactNode; href: string; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

import Sms from "app/frontend/pages/public/Sms";

// Submitted to Twilio's TCR verbatim — keep in sync with SMS_CONSENT_LABEL /
// SMS_CONSENT_DISCLOSURE in SmsNotificationsPanel.test.tsx.
const SMS_CONSENT_LABEL = "I agree to receive text messages from Sway";
const SMS_CONSENT_DISCLOSURE =
    "Sway sends 1-3 messages per week about new Bill of the Month legislation in your area, reminders to vote, and positions Sway records from organizations you follow. Msg&data rates may apply. Reply STOP to cancel, HELP for help.";

describe("public/Sms", () => {
    afterEach(() => {
        cleanup();
    });

    it("names the program", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getByRole("heading", { name: /Sway legislation alerts/ })).toBeTruthy();
    });

    it("lists Bill of the Month alerts as message types", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getByText(/New Bill of the Month alerts, for example:/)).toBeTruthy();
    });

    it("shows real Bill of the Month alert copy", () => {
        render(<Sms sms_phone={null} />);
        expect(
            screen.getByText('"New Bill of the Month in Baltimore: [bill title]. Check it out on Sway!"'),
        ).toBeTruthy();
    });

    it("shows real voting reminder copy", () => {
        render(<Sms sms_phone={null} />);
        expect(
            screen.getByText('"Sway: You haven\'t voted on the featured bill in Baltimore: [bill title]. Vote now!"'),
        ).toBeTruthy();
    });

    it("describes organization position notices", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getByText(/Organization position notices/)).toBeTruthy();
    });

    it("states frequency", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getAllByText(/1-3 messages per week/).length).toBeGreaterThan(0);
    });

    it("states carrier-required rate and opt-out disclosures", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getAllByText(/Msg&data rates may apply/).length).toBeGreaterThan(0);
        expect(screen.getByText(/Reply STOP to cancel\. Reply HELP for help\./)).toBeTruthy();
    });

    it("shows the sending number when the server provides one", () => {
        render(<Sms sms_phone="(410) 555-0123" />);
        expect(screen.getByText(/Messages come from/).textContent).toBe("Messages come from (410) 555-0123.");
    });

    it("omits the sending number line when no number is configured", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.queryByText(/Messages come from/)).toBeNull();
        expect(screen.queryByText(/Sway's phone number is/)).toBeNull();
    });

    it("labels the live consent panel as a non-interactive preview", () => {
        render(<Sms sms_phone={null} />);
        const figure = screen.getByRole("figure", { name: /Preview of the consent panel/ });
        expect(within(figure).getByText("Preview, not interactive")).toBeTruthy();
        expect(within(figure).getByTestId("sms-consent-preview")).toBeTruthy();
        expect(within(figure).getByText("Disabled")).toBeTruthy();
    });

    it("renders the exact consent checkbox label in the preview", () => {
        render(<Sms sms_phone={null} />);
        const figure = screen.getByRole("figure");
        expect(within(figure).getByText(SMS_CONSENT_LABEL)).toBeTruthy();
    });

    it("renders the exact consent disclosure paragraph in the preview", () => {
        render(<Sms sms_phone={null} />);
        const figure = screen.getByRole("figure");
        expect(within(figure).getByText(SMS_CONSENT_DISCLOSURE)).toBeTruthy();
    });

    it("renders a single consent checkbox, disabled and unchecked", () => {
        render(<Sms sms_phone={null} />);
        const checkboxes = screen.getAllByRole("checkbox");
        expect(checkboxes).toHaveLength(1);
        const checkbox = screen.getByRole("checkbox", { name: SMS_CONSENT_LABEL });
        expect(checkbox.hasAttribute("disabled")).toBe(true);
        expect(checkbox.getAttribute("aria-checked")).toBe("false");
    });

    it("disables the preview's save button", () => {
        render(<Sms sms_phone={null} />);
        const save = screen.getByRole("button", { name: "Save preferences" });
        expect(save.hasAttribute("disabled")).toBe(true);
    });

    it("states the box is unchecked by default and SMS is off for new accounts", () => {
        render(<Sms sms_phone={null} />);
        expect(screen.getByText(/unchecked by default/)).toBeTruthy();
    });

    it("links to the privacy policy", () => {
        render(<Sms sms_phone={null} />);
        const link = screen.getByRole("link", { name: "privacy policy" });
        expect(link.getAttribute("href")).toBe("/privacy");
    });

    it("links to the terms of service", () => {
        render(<Sms sms_phone={null} />);
        const link = screen.getByRole("link", { name: "terms of service" });
        expect(link.getAttribute("href")).toBe("/terms");
    });
});

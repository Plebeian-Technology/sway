import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen } from "@testing-library/react";

import SmsNotificationsPanel from "app/frontend/components/notifications/SmsNotificationsPanel";
import { renderV2, resetInertiaStubs, type InertiaStubs } from "./test-utils";
import type { sway } from "sway";

// ---------------------------------------------------------------------------
// Inertia mock — useForm is faked so the test controls what patch() does
// ---------------------------------------------------------------------------
const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} as Record<string, unknown> })),
    router: {
        visit: vi.fn<(...args: unknown[]) => void>(),
        post: vi.fn<(...args: unknown[]) => void>(),
        put: vi.fn<(...args: unknown[]) => void>(),
        patch: vi.fn<(...args: unknown[]) => void>(),
        delete: vi.fn<(...args: unknown[]) => void>(),
        get: vi.fn<(...args: unknown[]) => void>(),
        reload: vi.fn<(...args: unknown[]) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

const patchSpy = vi.hoisted(() => vi.fn<(url?: string, options?: Record<string, unknown>) => void>());

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    const react = await import("react");

    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
        useForm: (initialData: Record<string, unknown>) => {
            const [currentData, setCurrentData] = react.useState(() => ({
                ...(initialData as Record<string, unknown>),
            }));
            const setData = (key: string, value: unknown) => {
                setCurrentData((previous) => ({ ...previous, [key]: value }));
            };
            return {
                data: currentData,
                setData,
                patch: patchSpy,
                processing: false,
                errors: {},
            };
        },
    };
});

beforeEach(() => {
    resetInertiaStubs(inertia);
    patchSpy.mockReset();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const SMS_CONSENT_LABEL = "I agree to receive text messages from Sway";
const SMS_CONSENT_DISCLOSURE =
    "Sway sends 1-3 messages per week about new Bill of the Month legislation in your area, reminders to vote, and positions Sway records from organizations you track. Msg&data rates may apply. Reply STOP to cancel, HELP for help.";

const buildUser = (overrides: Partial<sway.IUser> = {}): sway.IUser =>
    ({
        sms_notifications_enabled: false,
        ...overrides,
    }) as sway.IUser;

const renderPanel = (props: Partial<React.ComponentProps<typeof SmsNotificationsPanel>> = {}) =>
    renderV2(<SmsNotificationsPanel user={buildUser()} sms_phone="+14105551234" {...props} />);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("SmsNotificationsPanel", () => {
    it("renders the consent checkbox unchecked when sms_notifications_enabled is false", () => {
        renderPanel({ user: buildUser({ sms_notifications_enabled: false }) });

        const checkbox = screen.getByRole("checkbox", { name: SMS_CONSENT_LABEL });
        expect(checkbox).toBeTruthy();
        expect(checkbox.getAttribute("aria-checked")).toBe("false");
    });

    it("renders the consent checkbox checked when sms_notifications_enabled is true", () => {
        renderPanel({ user: buildUser({ sms_notifications_enabled: true }) });

        const checkbox = screen.getByRole("checkbox", { name: SMS_CONSENT_LABEL });
        expect(checkbox.getAttribute("aria-checked")).toBe("true");
    });

    it("shows the exact consent label text", () => {
        renderPanel();
        expect(screen.getByText(SMS_CONSENT_LABEL)).toBeTruthy();
    });

    it("shows the exact disclosure paragraph text", () => {
        renderPanel();
        expect(screen.getByText(SMS_CONSENT_DISCLOSURE)).toBeTruthy();
    });

    it("links to the privacy policy", () => {
        renderPanel();
        const link = screen.getByRole("link", { name: "Privacy Policy" });
        expect(link.getAttribute("href")).toBe("/privacy");
    });

    it("links to the terms of service", () => {
        renderPanel();
        const link = screen.getByRole("link", { name: "Terms of Service" });
        expect(link.getAttribute("href")).toBe("/terms");
    });

    it("shows 'Disabled' badge when not opted in (default)", () => {
        renderPanel({ user: buildUser({ sms_notifications_enabled: false }) });
        expect(screen.getByText("Disabled")).toBeTruthy();
    });

    it("shows 'Enabled' badge when opted in", () => {
        renderPanel({ user: buildUser({ sms_notifications_enabled: true }) });
        expect(screen.getByText("Enabled")).toBeTruthy();
    });

    it("keeps the frequency sentence about Bills of the Month", () => {
        renderPanel();
        expect(screen.getByText(/Sway can keep you informed about new Bills of the Month/)).toBeTruthy();
    });

    it("keeps the STOP / START instructions", () => {
        renderPanel();
        expect(screen.getByText(/reply/)).toBeTruthy();
        expect(screen.getByText("START")).toBeTruthy();
        expect(screen.getByText("STOP")).toBeTruthy();
    });

    it("keeps the message and data rates fine print", () => {
        renderPanel();
        expect(screen.getByText(/Message and data rates may apply\./)).toBeTruthy();
    });

    // @lat: [[inbound-sms#Inbound SMS#The number's notice cannot deny receiving messages]]
    it("says replies are unmonitored rather than that the number cannot receive them", () => {
        renderPanel();
        expect(screen.getByText(/does not accept phone calls/)).toBeTruthy();
        expect(screen.getByText(/replies other than STOP, START and HELP are not monitored/)).toBeTruthy();
        expect(screen.queryByText(/cannot receive calls or messages/)).toBeNull();
    });

    it("keeps the Sway phone number and vcf download", () => {
        renderPanel({ sms_phone: "+14105551234" });
        expect(screen.getByText("+14105551234")).toBeTruthy();
        expect(screen.getByText("Download Sway contact (.vcf)")).toBeTruthy();
    });

    // @lat: [[sms-notification-service-design#Where the displayed Sway number comes from]]
    it("leaves out the phone number and vcf download when no number is configured", () => {
        renderPanel({ sms_phone: null });
        expect(screen.queryByText(/Sway's phone number is/)).toBeNull();
        expect(screen.queryByText("Download Sway contact (.vcf)")).toBeNull();
        expect(screen.getByText("START")).toBeTruthy();
    });
});

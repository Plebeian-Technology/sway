// @lat: [[frontend-test-infrastructure-notes#OrganizationsNotificationsPanel: the jest-dom matcher gap]]

import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, screen } from "@testing-library/react";

import OrganizationsNotificationsPanel from "app/frontend/components/notifications/OrganizationsNotificationsPanel";
import { renderV2, resetInertiaStubs, type InertiaStubs } from "./test-utils";

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

// The fake patch function handed to useForm, so the tests can watch the calls
const patchSpy = vi.hoisted(() => vi.fn<(options?: Record<string, unknown>) => void>());

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    const react = await import("react");

    // @lat: [[frontend-test-infrastructure-notes#OrganizationsNotificationsPanel: why the useForm stand-in must hold real state]]
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

// Stand in for the Select widget, because jsdom (the fake browser these tests
// run in) has no ResizeObserver and no working portals. The replacement is a
// plain <select>, so the tests can still read the option text.
vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({
        value,
        onValueChange,
        children,
    }: {
        value: string;
        onValueChange: (v: string) => void;
        children: React.ReactNode;
    }) => (
        <select value={value} onChange={(e) => onValueChange(e.target.value)}>
            {children}
        </select>
    ),
    SelectTrigger: () => null,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

beforeEach(() => {
    resetInertiaStubs(inertia);
    patchSpy.mockReset();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const renderPanel = (props: Partial<React.ComponentProps<typeof OrganizationsNotificationsPanel>> = {}) =>
    renderV2(<OrganizationsNotificationsPanel {...props} />);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("OrganizationsNotificationsPanel", () => {
    it("renders the card with correct title", () => {
        renderPanel();
        expect(screen.getByText("Organization position updates")).toBeTruthy();
    });

    it("shows body copy about organizations and legislation", () => {
        renderPanel();
        expect(
            screen.getByText(/Get notified when Sway records or updates a position from an organization you track/),
        ).toBeTruthy();
    });

    it("renders the master switch labelled 'Enable organization notifications'", () => {
        renderPanel();
        expect(screen.getByLabelText("Enable organization notifications")).toBeTruthy();
    });

    it("shows 'Disabled' badge when master is off (default)", () => {
        renderPanel({ org_position_taken: false });
        expect(screen.getByTestId("org-notifications-saved-state").textContent).toBe("Disabled");
    });

    it("shows 'Enabled' badge when master is on", () => {
        renderPanel({ org_position_taken: true });
        expect(screen.getByTestId("org-notifications-saved-state").textContent).toBe("Enabled");
    });

    // @lat: [[organization-follow-control#Following an organization#Why a switch and its badge read different sources]]
    it("keeps the badge on the saved value when the switch is clicked", () => {
        renderPanel({ org_position_taken: false });

        fireEvent.click(screen.getByLabelText("Enable organization notifications"));

        // The switch moved: the sections it gates are now on screen.
        expect(screen.getByText("Default for new follows")).toBeTruthy();
        // The badge did not.
        expect(screen.getByTestId("org-notifications-saved-state").textContent).toBe("Disabled");
    });

    it("marks the panel unsaved once the switch differs from the saved value", () => {
        renderPanel({ org_position_taken: false });
        expect(screen.queryByTestId("org-notifications-unsaved")).toBeNull();

        fireEvent.click(screen.getByLabelText("Enable organization notifications"));

        expect(screen.getByTestId("org-notifications-unsaved")).toBeTruthy();
    });

    it("enables Save once the switch differs from the saved value", () => {
        renderPanel({ org_position_taken: false });
        expect(screen.getByTestId("org-notifications-save").hasAttribute("disabled")).toBe(true);

        fireEvent.click(screen.getByLabelText("Enable organization notifications"));

        expect(screen.getByTestId("org-notifications-save").hasAttribute("disabled")).toBe(false);
    });

    it("hides the event-type checkboxes when master is off", () => {
        renderPanel({ org_position_taken: false });
        expect(screen.queryByText("Default for new follows")).toBeNull();
        expect(screen.queryByText("New position on a bill")).toBeNull();
    });

    it("shows event-type checkboxes and cadence when master is on", () => {
        renderPanel({ org_position_taken: true });
        expect(screen.getByText("Default for new follows")).toBeTruthy();
        expect(screen.getByText("New position on a bill")).toBeTruthy();
        expect(screen.getByText("Change in support (for/against)")).toBeTruthy();
        expect(screen.getByText("Summary update")).toBeTruthy();
        expect(screen.getByText("Default delivery")).toBeTruthy();
    });

    it("shows empty state copy when master is off", () => {
        renderPanel({ org_position_taken: false });
        expect(screen.getByText("Turn on organization notifications above to customize defaults.")).toBeTruthy();
    });

    it("renders the Save preferences button", () => {
        renderPanel();
        expect(screen.getByText("Save preferences")).toBeTruthy();
    });

    it("Save button is disabled when not dirty (props match form state)", () => {
        renderPanel({ org_position_taken: false });
        const btn = screen.getByTestId("org-notifications-save");
        // Nothing has changed yet: the form started out from the props.
        expect(btn.hasAttribute("disabled")).toBe(true);
    });

    it("submits patch to /notifications/org_defaults when form is submitted", () => {
        renderPanel({ org_position_taken: true });
        const form = screen.getByTestId("org-notifications-save").closest("form")!;
        fireEvent.submit(form);
        expect(patchSpy).toHaveBeenCalledWith("/notifications/org_defaults", { preserveScroll: true });
    });

    it("patches the notificationsOrgDefaults route specifically", () => {
        renderPanel({ org_position_taken: true });
        const form = screen.getByTestId("org-notifications-save").closest("form")!;
        fireEvent.submit(form);
        expect(patchSpy.mock.calls[0]?.[0]).toBe("/notifications/org_defaults");
    });

    it("contains all required copy strings from UI-SPEC Copywriting Contract", () => {
        renderPanel({ org_position_taken: true });
        expect(screen.getByText("Enable organization notifications")).toBeTruthy();
        expect(screen.getByText("Default for new follows")).toBeTruthy();
        expect(screen.getByText("Default delivery")).toBeTruthy();
        expect(screen.getByText("Save preferences")).toBeTruthy();
    });

    it("does not contain select-none anywhere in the rendered output", () => {
        const { container } = renderPanel({ org_position_taken: true });
        expect(container.innerHTML).not.toContain("select-none");
    });

    it("shows cadence options when master is on", () => {
        renderPanel({ org_position_taken: true });
        expect(screen.getByText("Every change")).toBeTruthy();
        expect(screen.getByText("Daily digest")).toBeTruthy();
        expect(screen.getByText("Weekly digest")).toBeTruthy();
    });
});

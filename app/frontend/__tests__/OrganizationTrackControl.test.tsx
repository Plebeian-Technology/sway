// @lat: [[organization-track-control-test-regressions#OrganizationFollowControl: two regression guards]]

import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, screen } from "@testing-library/react";
import type { ComponentProps } from "react";

import OrganizationTrackControl from "app/frontend/components/organizations/OrganizationTrackControl";
import { renderV2, resetInertiaStubs, type InertiaStubs } from "./test-utils";
import { sway } from "sway";

// By repo convention a component does not export its IProps interface, so read
// the shape of the props back off the component itself.
type OrganizationTrackControlProps = ComponentProps<typeof OrganizationTrackControl>;

// ---------------------------------------------------------------------------
// Inertia mock
// ---------------------------------------------------------------------------
const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(),
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

const postSpy = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const deleteSpy = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const patchSpy = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
        useForm: (initialData: Record<string, unknown>) => {
            const data = { ...(initialData as Record<string, unknown>) };
            return {
                data,
                setData: vi.fn<(key: string, value: unknown) => void>(),
                post: postSpy,
                patch: patchSpy,
                delete: deleteSpy,
                processing: false,
                errors: {},
            };
        },
    };
});

// Stand in for the Select widget: the real Radix UI one does not work in jsdom,
// the fake browser these tests run in.
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

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
const org: sway.IPublicOrganization = {
    id: 42,
    name: "Civic League",
    sway_locale_id: 1,
};

const savedFollowPrefs: sway.IOrgFollowPrefs = {
    follow_id: 99,
    notify_on_new_position: false,
    notify_on_support_change: true,
    notify_on_summary_change: false,
    notification_cadence: "daily",
    muted: false,
};

const orgDefaults: sway.IOrgDefaultPrefs = {
    notify_on_new_position: true,
    notify_on_support_change: true,
    notify_on_summary_change: true,
    notification_cadence: "every_change",
};

const defaultProps: OrganizationTrackControlProps = {
    organization: org,
    followId: null,
    isMember: false,
    isMuted: false,
    isSignedIn: true,
    masterEnabled: true,
};

beforeEach(() => {
    resetInertiaStubs(inertia);
    postSpy.mockReset();
    deleteSpy.mockReset();
    patchSpy.mockReset();
});

const renderControl = (overrides: Partial<OrganizationTrackControlProps> = {}) =>
    renderV2(<OrganizationTrackControl {...defaultProps} {...overrides} />);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("OrganizationTrackControl — signed-out", () => {
    it("renders nothing when signed out", () => {
        const { container } = renderControl({ isSignedIn: false });
        // renderV2 puts everything inside a <div data-theme="v2">, so look
        // inside that wrapper: the component itself should render nothing when
        // the visitor is signed out.
        const wrapper = container.firstChild as HTMLElement;
        expect(wrapper?.firstChild).toBeNull();
    });
});

describe("OrganizationTrackControl — not following (signed-in, non-member)", () => {
    it("renders a Follow button", () => {
        renderControl({ followId: null, isMember: false });
        expect(screen.getByTestId("follow-btn-42")).toBeTruthy();
        expect(screen.getByText("Follow")).toBeTruthy();
    });

    it("does not render an Unfollow or Tracking button", () => {
        renderControl({ followId: null, isMember: false });
        expect(screen.queryByText("Tracking")).toBeNull();
        expect(screen.queryByText("Unfollow")).toBeNull();
    });

    it("POSTs to /organization_tracks on Follow submit", () => {
        renderControl({ followId: null, isMember: false });
        const form = screen.getByTestId("follow-btn-42").closest("form")!;
        fireEvent.submit(form);
        expect(postSpy).toHaveBeenCalledWith("/organization_tracks", expect.objectContaining({ preserveScroll: true }));
    });

    it("does not use fetch or axios (Inertia PRG assertion)", () => {
        // Watch the global fetch, so that if someone later adds a raw fetch
        // next to the useForm post, this test catches it. The old version of
        // this test only proved post() ran.
        const fetchSpy = vi.fn<(...args: unknown[]) => unknown>();
        vi.stubGlobal("fetch", fetchSpy);
        try {
            renderControl({ followId: null, isMember: false });
            const form = screen.getByTestId("follow-btn-42").closest("form")!;
            fireEvent.submit(form);
            // useForm sends the request through Inertia (post, then redirect,
            // then get) — never a raw fetch or axios call.
            expect(postSpy).toHaveBeenCalled();
            expect(fetchSpy).not.toHaveBeenCalled();
        } finally {
            vi.unstubAllGlobals();
        }
    });
});

describe("OrganizationTrackControl — following (non-member)", () => {
    it("renders an 'Unfollow' button, with the follow state shown on the card instead of a badge here", () => {
        renderControl({ followId: 99, isMember: false });
        expect(screen.getByTestId("following-btn-42")).toBeTruthy();
        expect(screen.getByText("Unfollow", { selector: "button" })).toBeTruthy();
        expect(screen.queryByText("Tracking", { selector: "span[data-slot='badge']" })).toBeNull();
    });

    it("DELETEs to /organization_tracks/:id on Tracking submit", () => {
        renderControl({ followId: 99, isMember: false });
        const form = screen.getByTestId("following-btn-42").closest("form")!;
        fireEvent.submit(form);
        expect(deleteSpy).toHaveBeenCalledWith(
            "/organization_tracks/99",
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("renders a Preferences button that opens the picker", () => {
        renderControl({ followId: 99, isMember: false });
        expect(screen.getByTestId("preferences-btn-42")).toBeTruthy();
    });

    it("does NOT render a member badge", () => {
        renderControl({ followId: 99, isMember: false });
        expect(screen.queryByText("Tracking · member")).toBeNull();
        expect(screen.queryByText("Muted · member")).toBeNull();
    });

    it("clicking Preferences opens the picker dialog", () => {
        renderControl({ followId: 99, isMember: false, trackPrefs: savedFollowPrefs });
        const prefBtn = screen.getByTestId("preferences-btn-42");
        fireEvent.click(prefBtn);
        // The dialog's contents should be on screen now.
        expect(screen.getByText("Notification preferences")).toBeTruthy();
    });

    it("Preferences Save PATCHes to /organization_tracks/:id/preferences (never /0/preferences)", () => {
        renderControl({ followId: 99, isMember: false, trackPrefs: savedFollowPrefs });
        fireEvent.click(screen.getByTestId("preferences-btn-42"));
        const saveBtn = screen.getByText("Save preferences");
        const form = saveBtn.closest("form")!;
        fireEvent.submit(form);
        expect(patchSpy).toHaveBeenCalledWith(
            "/organization_tracks/99/preferences",
            expect.objectContaining({ preserveScroll: true }),
        );
        // It must never aim at the broken URL that has a zero for the id.
        expect(patchSpy).not.toHaveBeenCalledWith("/organization_tracks/0/preferences", expect.anything());
    });
});

describe("OrganizationTrackControl — member with followId", () => {
    it("renders 'Tracking · member' badge", () => {
        renderControl({ followId: 99, isMember: true, isMuted: false });
        expect(screen.getByTestId("member-badge-42")).toBeTruthy();
        expect(screen.getByText("Tracking · member")).toBeTruthy();
    });

    it("renders Preferences button (not Unfollow) — no-Unfollow rule", () => {
        renderControl({ followId: 99, isMember: true });
        expect(screen.getByTestId("member-preferences-btn-42")).toBeTruthy();
        // Spelled out: no form with an Unfollow or Tracking submit button.
        expect(screen.queryByTestId("following-btn-42")).toBeNull();
        expect(screen.queryByText("Follow", { selector: "button" })).toBeNull();
    });

    it("does NOT render a Follow or Tracking submit button — no Unfollow for members", () => {
        renderControl({ followId: 99, isMember: true });
        // Members get no delete or unfollow form at all.
        expect(screen.queryByTestId("following-btn-42")).toBeNull();
        expect(screen.queryByTestId("follow-btn-42")).toBeNull();
    });
});

describe("OrganizationTrackControl — member with NO follow row", () => {
    it("renders 'Tracking · member' badge even without followId", () => {
        renderControl({ followId: null, isMember: true, isMuted: false });
        expect(screen.getByText("Tracking · member")).toBeTruthy();
    });

    it("renders Preferences button even without followId", () => {
        renderControl({ followId: null, isMember: true });
        expect(screen.getByTestId("member-preferences-btn-42")).toBeTruthy();
    });

    it("does NOT render Follow or Unfollow buttons — member branch unconditional", () => {
        renderControl({ followId: null, isMember: true });
        expect(screen.queryByTestId("follow-btn-42")).toBeNull();
        expect(screen.queryByTestId("following-btn-42")).toBeNull();
    });

    // Clicking Preferences must open the picker. An old check on followId
    // swallowed that click without a word, so this test would have failed then.
    it("clicking Preferences opens the picker modal (WR-13 regression)", () => {
        renderControl({ followId: null, isMember: true, orgDefaults });
        const prefBtn = screen.getByTestId("member-preferences-btn-42");
        fireEvent.click(prefBtn);
        // The picker dialog's contents should be on screen now.
        expect(screen.getByText("Notification preferences")).toBeTruthy();
    });

    // With no follow row yet, Save must POST to /organization_tracks rather
    // than PATCH /0/preferences.
    it("Save in create mode POSTs to /organization_tracks (never /0/preferences) (WR-13 regression)", () => {
        renderControl({ followId: null, isMember: true, orgDefaults });
        fireEvent.click(screen.getByTestId("member-preferences-btn-42"));
        const saveBtn = screen.getByText("Save preferences");
        const form = saveBtn.closest("form")!;
        fireEvent.submit(form);
        // It posts to the create route: the follow row is made when Save runs.
        expect(postSpy).toHaveBeenCalledWith("/organization_tracks", expect.objectContaining({ preserveScroll: true }));
        // It must never PATCH the broken /0/preferences URL.
        expect(patchSpy).not.toHaveBeenCalledWith("/organization_tracks/0/preferences", expect.anything());
    });

    // The picker starts from orgDefaults instead of switching everything on.
    it("picker is seeded from orgDefaults when no follow row (WR-10 CR-04)", () => {
        const customDefaults: sway.IOrgDefaultPrefs = {
            notify_on_new_position: false,
            notify_on_support_change: true,
            notify_on_summary_change: false,
            notification_cadence: "weekly",
        };
        renderControl({ followId: null, isMember: true, orgDefaults: customDefaults });
        fireEvent.click(screen.getByTestId("member-preferences-btn-42"));

        // Check the picker really starts from customDefaults, not from a
        // hardcoded everything-on / every_change. The (faked) cadence dropdown
        // shows "weekly", and the "New position" checkbox is unchecked, which
        // matches notify_on_new_position: false.
        expect((screen.getByRole("combobox") as HTMLSelectElement).value).toBe("weekly");
        expect(screen.getByRole("checkbox", { name: "New position on a bill" }).getAttribute("aria-checked")).toBe(
            "false",
        );
        // And the other way round: an event type that defaults to on is checked.
        expect(
            screen.getByRole("checkbox", { name: "Change in support (for/against)" }).getAttribute("aria-checked"),
        ).toBe("true");
    });
});

describe("OrganizationTrackControl — muted member", () => {
    it("renders 'Muted · member' badge when isMuted=true", () => {
        renderControl({ followId: 99, isMember: true, isMuted: true });
        expect(screen.getByText("Muted · member")).toBeTruthy();
    });

    it("still renders Preferences button for muted member", () => {
        renderControl({ followId: 99, isMember: true, isMuted: true });
        expect(screen.getByTestId("member-preferences-btn-42")).toBeTruthy();
    });
});

describe("OrganizationTrackControl — pref seeding (CR-04)", () => {
    it("picker opens and Save PATCHes to the correct follow preferences URL", () => {
        renderControl({ followId: 99, isMember: false, trackPrefs: savedFollowPrefs });
        fireEvent.click(screen.getByTestId("preferences-btn-42"));
        const form = screen.getByText("Save preferences").closest("form")!;
        fireEvent.submit(form);
        expect(patchSpy).toHaveBeenCalledWith(
            "/organization_tracks/99/preferences",
            expect.objectContaining({ preserveScroll: true }),
        );
    });
});

describe("OrganizationTrackControl — no select-none", () => {
    it("does not use select-none in any rendered state (project rule)", () => {
        const { container } = renderControl({ followId: 99, isMember: true });
        expect(container.innerHTML).not.toContain("select-none");
    });
});

// @lat: [[organization-follow-control#Why the control carries no aria-pressed]]
describe("OrganizationTrackControl — an action button, not a toggle", () => {
    it("names the action on the follow button and reports no pressed state", () => {
        renderControl({ followId: null, isMember: false });

        const follow = screen.getByRole("button", { name: "Follow" });
        expect(follow.getAttribute("aria-pressed")).toBeNull();
    });

    it("names the organization on the unfollow button and reports no pressed state", () => {
        renderControl({ followId: 99, isMember: false });

        const unfollow = screen.getByRole("button", { name: "Unfollow Civic League" });
        expect(unfollow).toBe(screen.getByTestId("following-btn-42"));
        expect(unfollow.getAttribute("aria-pressed")).toBeNull();
    });
});

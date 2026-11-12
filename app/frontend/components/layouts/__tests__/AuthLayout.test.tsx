// @lat: [[system-shape#System shape#Auth navigation]]

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, within } from "@testing-library/react";

import { renderV2, resetInertiaStubs, type InertiaStubs } from "app/frontend/__tests__/test-utils";
import { pendingVisitFixture } from "app/frontend/navigation/__tests__/pendingVisitFixture";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown>; url: string }>(() => ({
        props: {} as Record<string, unknown>,
        url: "/",
    })),
    router: {
        visit: vi.fn<(url: string, options?: unknown) => void>(),
        post: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
        put: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
        delete: vi.fn<(url: string, options?: unknown) => void>(),
        get: vi.fn<(url: string, options?: unknown) => void>(),
        reload: vi.fn<(options?: unknown) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
        // Head emits child <link>/<meta> tags into document.head via portal;
        // in jsdom this can race with renderV2's mount — stub as a no-op so
        // the test doesn't depend on the SSR-equivalent head behavior.
        Head: () => null,
    };
});

// useLogout returns a no-op promise resolver so Sign Out doesn't try to
// hit WebAuthn endpoints during the test.
vi.mock("app/frontend/hooks/users/useLogout", () => ({
    useLogout: () => () => Promise.resolve(),
}));

// useReachability runs a real `fetch` poll — stub it out so the test
// doesn't hit the network.
vi.mock("app/frontend/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, lastChecked: new Date() }),
}));

// useOfflineBannerState reads from useReachability and manages local
// state — stub it, defaulting to "hidden" so the banner does not render.
const offline = vi.hoisted(() => ({ bannerState: "hidden" as "hidden" | "visible" | "asserted" }));

vi.mock("app/frontend/hooks/useOfflineBannerState", () => ({
    useOfflineBannerState: () => ({
        bannerState: offline.bannerState,
        dismissBanner: () => {},
        assertBanner: () => {},
    }),
}));

// SWUpdateToast subscribes to the service worker (SW) lifecycle, which isn't
// available in jsdom — stub it as a no-op so it doesn't try to attach
// listeners.
vi.mock("app/frontend/components/offline/SWUpdateToast", () => ({
    SWUpdateToast: () => null,
}));

import { AuthLayout } from "app/frontend/components/layouts/AuthLayout";

const setPage = (overrides: {
    url?: string;
    user?: Partial<{ id: number; is_admin: boolean; is_registration_complete: boolean; beszel_url?: string }>;
}) => {
    inertia.usePage.mockReturnValue({
        url: overrides.url ?? "/",
        props: {
            // Defaults come FIRST so overrides win — this order used to be
            // reversed, which meant any overrides.user.id was silently
            // overwritten by `id: 1`.
            user: { id: 1, is_admin: false, is_registration_complete: true, ...overrides.user },
        } as Record<string, unknown>,
    });
};

// @lat: [[drawer-header-and-nav-selection#Where the mobile header's page name comes from]]
type Queries = ReturnType<typeof renderV2>;

const navLink = (queryByRole: Queries["queryByRole"], label: string): HTMLElement | null =>
    queryByRole("link", { name: label });

beforeEach(() => {
    resetInertiaStubs(inertia);
    offline.bannerState = "hidden";
});

describe("AuthLayout — admin-mode Drawer flip", () => {
    it("renders admin-mode primary nav when URL starts with /admin AND user is sway_admin", () => {
        setPage({ url: "/admin", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
        expect(navLink(queryByRole, "Bill Creator")).not.toBeNull();
        expect(navLink(queryByRole, "LLM Settings")).not.toBeNull();
        expect(navLink(queryByRole, "Beszel")).toBeNull();
        expect(navLink(queryByRole, "Representatives")).toBeNull();
        expect(navLink(queryByRole, "Bill of the Month")).toBeNull();
        expect(navLink(queryByRole, "Past Bills of the Month")).toBeNull();
        expect(navLink(queryByRole, "All Bills")).toBeNull();
        expect(navLink(queryByRole, "Your Sway")).toBeNull();
    });

    it("renders the external Beszel link in admin-mode primary nav when user.beszel_url is present", () => {
        setPage({
            url: "/admin",
            user: { is_admin: true, is_registration_complete: true, beszel_url: "http://203.0.113.10:8090" },
        });
        const { queryByRole } = renderV2(<AuthLayout />);

        const beszelLink = navLink(queryByRole, "Beszel");
        expect(beszelLink).not.toBeNull();
        expect(beszelLink).toHaveAttribute("href", "http://203.0.113.10:8090");
        expect(beszelLink).toHaveAttribute("target", "_blank");
    });

    it("renders admin-mode primary nav on a deeper /admin/llm_settings route", () => {
        setPage({ url: "/admin/llm_settings", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
        expect(navLink(queryByRole, "LLM Settings")).not.toBeNull();
        expect(navLink(queryByRole, "Representatives")).toBeNull();
    });

    it("renders admin-mode primary nav on a /admin/bill_creator/:id/edit deep route", () => {
        setPage({ url: "/admin/bill_creator/42/edit", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Bill Creator")).not.toBeNull();
        expect(navLink(queryByRole, "Representatives")).toBeNull();
    });

    it("renders user-facing nav outside the /admin namespace even when user is sway_admin", () => {
        setPage({ url: "/legislators", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole, getAllByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Feed")).toHaveAttribute("href", "/feed");
        expect(getAllByRole("link").find((el) => el.getAttribute("href") === "/feed")?.textContent).toContain("Feed");
        expect(navLink(queryByRole, "Representatives")).not.toBeNull();
        expect(navLink(queryByRole, "Bill of the Month")).not.toBeNull();
        expect(navLink(queryByRole, "Past Bills of the Month")).toHaveAttribute("href", "/past_bills_of_the_month");
        expect(navLink(queryByRole, "All Bills")).toHaveAttribute("href", "/bills");
        expect(navLink(queryByRole, "Admin Home")).toBeNull();
        // user-mode secondary nav still surfaces the "Admin" entry that links to /admin
        expect(navLink(queryByRole, "Admin")).not.toBeNull();
    });

    it("places Feed first in the signed-in primary navigation list", () => {
        setPage({ url: "/feed", user: { is_admin: false, is_registration_complete: true } });
        const { getAllByRole } = renderV2(<AuthLayout />);

        const navLinks = getAllByRole("link").filter((el) => el.getAttribute("href") !== "/");
        expect(navLinks[0]).toHaveAttribute("href", "/feed");
        expect(navLinks[1]).toHaveAttribute("href", "/legislators");
    });

    it("labels the influence nav item 'Your Sway', matching the page heading and the terminology canon", () => {
        setPage({ url: "/legislators", user: { is_admin: false, is_registration_complete: true } });
        const { queryByText } = renderV2(<AuthLayout />);

        expect(queryByText("Your Sway")).not.toBeNull();
        expect(queryByText("Your sway")).toBeNull();
    });

    it("renders user-facing nav at /admin when user is NOT sway_admin (gate requires both)", () => {
        setPage({ url: "/admin", user: { is_admin: false, is_registration_complete: true } });
        const { queryByText } = renderV2(<AuthLayout />);

        expect(queryByText("Representatives")).not.toBeNull();
        expect(queryByText("Admin Home")).toBeNull();
    });

    it("locks the admin-mode prefix to /admin namespace boundary (F-i1-WR-004)", () => {
        setPage({ url: "/administrators", user: { is_admin: true, is_registration_complete: true } });
        const { queryByText } = renderV2(<AuthLayout />);

        expect(queryByText("Admin Home")).toBeNull();
        expect(queryByText("Representatives")).not.toBeNull();
    });

    it("surfaces a 'Back to Sway' affordance in the admin-mode secondary nav", () => {
        setPage({ url: "/admin", user: { is_admin: true, is_registration_complete: true } });
        const { queryByText } = renderV2(<AuthLayout />);

        expect(queryByText("Back to Sway")).not.toBeNull();
        // Notifications + Organizations belong to user surface, not operator.
        expect(queryByText("Organizations")).toBeNull();
    });
});

describe("AuthLayout — admin-mode active-state (F-i1-WR-007 + F-i2-WR-002)", () => {
    it("lights up 'Bill Creator' (aria-current=page) on a /admin/bill_creator/:id/edit deep route", () => {
        setPage({ url: "/admin/bill_creator/42/edit", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Bill Creator")?.getAttribute("aria-current")).toBe("page");
        expect(navLink(queryByRole, "LLM Settings")?.getAttribute("aria-current")).toBeNull();
        expect(navLink(queryByRole, "Admin Home")?.getAttribute("aria-current")).toBeNull();
    });

    it("lights up 'Admin Home' only on exact /admin (not on sub-routes)", () => {
        setPage({ url: "/admin", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")?.getAttribute("aria-current")).toBe("page");
    });

    it("does NOT light up 'Admin Home' inside /admin/llm_settings, but DOES light up 'LLM Settings'", () => {
        setPage({ url: "/admin/llm_settings", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")?.getAttribute("aria-current")).toBeNull();
        expect(navLink(queryByRole, "LLM Settings")?.getAttribute("aria-current")).toBe("page");
    });

    it("stays in admin mode when /admin has a query string (F-i3-WR-001) — was flipping out", () => {
        setPage({ url: "/admin?return_to=/legislators", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
        expect(navLink(queryByRole, "Representatives")).toBeNull();
    });

    it("stays in admin mode when /admin has a hash fragment (F-i3-WR-001)", () => {
        setPage({ url: "/admin#tools", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
    });

    it("stays in admin mode when /admin has a bare trailing ? (F-i4-IN-002)", () => {
        setPage({ url: "/admin?", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
    });

    it("stays in admin mode when /admin has a bare trailing # (F-i4-IN-002)", () => {
        setPage({ url: "/admin#", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "Admin Home")).not.toBeNull();
    });

    it("lights up 'LLM Settings' when URL has a hash fragment (F-i4-WR-001)", () => {
        // The Drawer's path-normalization must strip the hash too, otherwise
        // /admin/llm_settings#models leaves the sidebar entry dark even though
        // the operator is plainly on the LLM Settings page.
        setPage({ url: "/admin/llm_settings#models", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        expect(navLink(queryByRole, "LLM Settings")?.getAttribute("aria-current")).toBe("page");
    });

    it("respects namespace-boundary lock on activePrefix (F-i2-WR-004) — /admin/bill_creator_archive does NOT light Bill Creator", () => {
        // Hypothetical sibling namespace sharing a substring prefix. activePrefix is "/admin/bill_creator" —
        // boundary-lock requires an exact match or a "/" boundary, so the archive route should NOT match.
        setPage({ url: "/admin/bill_creator_archive", user: { is_admin: true, is_registration_complete: true } });
        const { queryByRole } = renderV2(<AuthLayout />);
        // /admin/bill_creator_archive starts with /admin/ so we're still in
        // admin mode — Bill Creator entry must render but NOT be lit.
        expect(navLink(queryByRole, "Bill Creator")?.getAttribute("aria-current")).toBeNull();
    });
});

describe("AuthLayout — passkey navigation", () => {
    it.each([
        { url: "/users/passkeys", is_admin: false },
        { url: "/admin", is_admin: true },
    ])("links signed-in users to passkeys from $url", ({ url, is_admin }) => {
        setPage({ url, user: { is_admin } });
        const { getByRole } = renderV2(<AuthLayout />);

        const link = getByRole("link", { name: "Passkeys" });
        expect(link).toHaveAttribute("href", "/users/passkeys");
        expect(link.getAttribute("aria-current")).toBe(url === "/users/passkeys" ? "page" : null);
    });

    it("includes Passkeys when the mobile navigation drawer opens", () => {
        setPage({ url: "/legislators" });
        const { getByRole } = renderV2(<AuthLayout />);

        fireEvent.click(getByRole("button", { name: "Open navigation drawer" }));

        const drawer = getByRole("dialog", { name: "Navigate Sway" });
        expect(within(drawer).getByRole("link", { name: "Passkeys" })).toHaveAttribute("href", "/users/passkeys");
    });

    it("hides the passkey link from guests", () => {
        inertia.usePage.mockReturnValue({ url: "/", props: { user: null } });
        const { queryByRole } = renderV2(<AuthLayout />);

        expect(navLink(queryByRole, "Passkeys")).toBeNull();
    });
});

const dispatchInertia = (name: string, detail: Record<string, unknown> = {}): void => {
    act(() => {
        document.dispatchEvent(new CustomEvent(`inertia:${name}`, { cancelable: true, detail }));
    });
};

describe("AuthLayout — PageBodySlot treated region", () => {
    afterEach(() => {
        dispatchInertia("finish");
    });

    it("keeps every Drawer nav link and the app-version footer outside the inert treated region during a qualifying visit", () => {
        setPage({ url: "/legislators", user: { is_admin: false, is_registration_complete: true } });
        const { container } = renderV2(<AuthLayout />);

        dispatchInertia("before", {
            visit: pendingVisitFixture({ url: new URL("/bill_of_the_month", window.location.href) }),
        });

        expect(container.querySelectorAll("[inert] a").length).toBe(0);

        const footer = container.querySelector("footer");
        expect(footer).not.toBeNull();
        expect(footer?.closest("[inert]")).toBeNull();
    });

    it("speaks through exactly one live region during a qualifying visit, and it is the loading announcement, not the Drawer's navigating word", () => {
        setPage({ url: "/legislators", user: { is_admin: false, is_registration_complete: true } });
        const { container } = renderV2(<AuthLayout />);

        dispatchInertia("before", {
            visit: pendingVisitFixture({ url: new URL("/bill_of_the_month", window.location.href) }),
        });

        const speaking = Array.from(container.querySelectorAll("[aria-live]")).filter(
            (el) => (el.textContent ?? "").trim().length > 0,
        );
        expect(speaking).toHaveLength(1);
        expect(speaking[0].textContent).toContain("Loading");
        expect(speaking[0].textContent).not.toContain("Navigating");
    });
});

describe("AuthLayout — offline banner colour", () => {
    it("draws the offline notice with the warning tokens, not the colour reserved for danger", () => {
        offline.bannerState = "visible";
        setPage({ url: "/legislators", user: { is_admin: false, is_registration_complete: true } });
        const { getByTestId } = renderV2(<AuthLayout />);

        const banner = getByTestId("offline-banner");
        expect(banner.textContent).toContain("You're offline. Reconnect to load pages and vote.");
        expect(banner.className.split(" ")).toContain("block");
        expect(banner.className).toContain("bg-warning");
        expect(banner.className).toContain("text-warning-foreground");
        expect(banner.className).not.toContain("bg-destructive");
    });

    it("keeps the asserted 'Still offline' state off the destructive colour too", () => {
        offline.bannerState = "asserted";
        setPage({ url: "/legislators", user: { is_admin: false, is_registration_complete: true } });
        const { getByTestId } = renderV2(<AuthLayout />);

        const banner = getByTestId("offline-banner");
        expect(banner.textContent).toContain("Still offline. Reconnect to load pages and vote.");
        expect(banner.className).not.toContain("bg-destructive");
    });
});

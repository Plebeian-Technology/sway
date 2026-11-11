import { describe, expect, it } from "vitest";
import {
    isNavigationExcludedRoute,
    NAVIGATION_EXCLUDED_ROUTE_PREFIXES,
    normalizeNavigationPathname,
    PREFETCH_CACHE_FOR,
} from "app/frontend/sway_constants/navigation";

// @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
describe("NAVIGATION_EXCLUDED_ROUTE_PREFIXES and isNavigationExcludedRoute", () => {
    describe("constant definitions", () => {
        it("exports an array of excluded route prefixes", () => {
            expect(Array.isArray(NAVIGATION_EXCLUDED_ROUTE_PREFIXES)).toBe(true);
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES.length).toBeGreaterThan(0);
        });

        it("contains the core API and auth route prefixes", () => {
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/api/v1");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/api");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/sessions");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/test/sessions");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/passkeys");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/registrations");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/phone_verification");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/sway_registration");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/users/webauthn");
            expect(NAVIGATION_EXCLUDED_ROUTE_PREFIXES).toContain("/users/passkeys");
        });

        it("exports the stale-while-revalidate prefetch cache window", () => {
            expect(PREFETCH_CACHE_FOR).toEqual(["30s", "5m"]);
        });
    });

    describe("normalizeNavigationPathname", () => {
        it("strips query parameters and fragments", () => {
            expect(normalizeNavigationPathname("/bills?sort=title#results")).toBe("/bills");
            expect(normalizeNavigationPathname("/api/v1/sessions?token=123#auth")).toBe("/api/v1/sessions");
        });

        it("strips protocol and host from full URLs", () => {
            expect(normalizeNavigationPathname("https://sway.vote/api/v1/sessions?tab=foo")).toBe("/api/v1/sessions");
            expect(normalizeNavigationPathname("http://localhost:3333/bills#top")).toBe("/bills");
        });

        it("normalizes trailing slashes except for root", () => {
            expect(normalizeNavigationPathname("/bills/")).toBe("/bills");
            expect(normalizeNavigationPathname("/api/v1/")).toBe("/api/v1");
            expect(normalizeNavigationPathname("/")).toBe("/");
        });

        it("handles empty or blank values safely", () => {
            expect(normalizeNavigationPathname("")).toBe("");
            expect(normalizeNavigationPathname("   ")).toBe("");
            expect(normalizeNavigationPathname(null as unknown as string)).toBe("");
            expect(normalizeNavigationPathname(undefined as unknown as string)).toBe("");
        });
    });

    describe("a) API routes exclusion", () => {
        it("identifies routes under /api/v1 as excluded", () => {
            expect(isNavigationExcludedRoute("/api/v1")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/sessions")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/sessions/challenge")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/sessions/discoverable_challenge")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/passkeys")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/registrations")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/phone_verification")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/phone_verification/verify")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/devices")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/bootstrap")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/notification_preferences")).toBe(true);
        });

        it("identifies routes under /api as excluded", () => {
            expect(isNavigationExcludedRoute("/api")).toBe(true);
            expect(isNavigationExcludedRoute("/api/")).toBe(true);
            expect(isNavigationExcludedRoute("/api/bills")).toBe(true);
            expect(isNavigationExcludedRoute("/api/bills/101")).toBe(true);
            expect(isNavigationExcludedRoute("/api/districts")).toBe(true);
            expect(isNavigationExcludedRoute("/api/legislators")).toBe(true);
            expect(isNavigationExcludedRoute("/api/organizations")).toBe(true);
            expect(isNavigationExcludedRoute("/api/admin/bills")).toBe(true);
            expect(isNavigationExcludedRoute("/api/admin/organizations")).toBe(true);
        });
    });

    describe("b) Authentication, passkey, and registration routes exclusion", () => {
        it("identifies /sessions and /test/sessions as excluded", () => {
            expect(isNavigationExcludedRoute("/sessions")).toBe(true);
            expect(isNavigationExcludedRoute("/sessions/new")).toBe(true);
            expect(isNavigationExcludedRoute("/sessions/123")).toBe(true);
            expect(isNavigationExcludedRoute("/test/sessions")).toBe(true);
            expect(isNavigationExcludedRoute("/test/sessions/new")).toBe(true);
        });

        it("identifies /passkeys and /users/passkeys as excluded", () => {
            expect(isNavigationExcludedRoute("/passkeys")).toBe(true);
            expect(isNavigationExcludedRoute("/passkeys/callback")).toBe(true);
            expect(isNavigationExcludedRoute("/users/passkeys")).toBe(true);
            expect(isNavigationExcludedRoute("/users/passkeys/verify_phone")).toBe(true);
            expect(isNavigationExcludedRoute("/users/passkeys/confirm_phone")).toBe(true);
            expect(isNavigationExcludedRoute("/users/passkeys/add_options")).toBe(true);
            expect(isNavigationExcludedRoute("/users/passkeys/add_callback")).toBe(true);
        });

        it("identifies /registrations as excluded", () => {
            expect(isNavigationExcludedRoute("/registrations")).toBe(true);
            expect(isNavigationExcludedRoute("/registrations/callback")).toBe(true);
        });

        it("identifies /phone_verification as excluded", () => {
            expect(isNavigationExcludedRoute("/phone_verification")).toBe(true);
            expect(isNavigationExcludedRoute("/phone_verification/verify")).toBe(true);
            expect(isNavigationExcludedRoute("/phone_verification/1")).toBe(true);
        });

        it("identifies /sway_registration as excluded", () => {
            expect(isNavigationExcludedRoute("/sway_registration")).toBe(true);
            expect(isNavigationExcludedRoute("/sway_registration/new")).toBe(true);
            expect(isNavigationExcludedRoute("/sway_registration/123")).toBe(true);
        });

        it("identifies /users/webauthn routes as excluded", () => {
            expect(isNavigationExcludedRoute("/users/webauthn")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/sessions")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/sessions/callback")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/sessions/discoverable_challenge")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/registration")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/registration/callback")).toBe(true);
        });
    });

    describe("c) Standard navigation routes are NOT excluded", () => {
        it("allows primary reader pages", () => {
            expect(isNavigationExcludedRoute("/")).toBe(false);
            expect(isNavigationExcludedRoute("/bills")).toBe(false);
            expect(isNavigationExcludedRoute("/bills/42")).toBe(false);
            expect(isNavigationExcludedRoute("/bills/42/summary_reports")).toBe(false);
            expect(isNavigationExcludedRoute("/bill_of_the_month")).toBe(false);
            expect(isNavigationExcludedRoute("/legislators")).toBe(false);
            expect(isNavigationExcludedRoute("/legislators/7")).toBe(false);
            expect(isNavigationExcludedRoute("/notifications")).toBe(false);
            expect(isNavigationExcludedRoute("/influence")).toBe(false);
        });

        it("allows public organization pages", () => {
            expect(isNavigationExcludedRoute("/public/organizations")).toBe(false);
            expect(isNavigationExcludedRoute("/public/organizations/5")).toBe(false);
        });

        it("allows admin creator and settings surfaces", () => {
            expect(isNavigationExcludedRoute("/admin")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/new")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/42/creator")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/42/pipeline")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/42/summary")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/42/positions")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_creator/42/schedule")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/categories")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/llm_settings")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/bill_summary_reports")).toBe(false);
            expect(isNavigationExcludedRoute("/admin/registration_funnel")).toBe(false);
        });

        it("allows user account settings and memberships", () => {
            expect(isNavigationExcludedRoute("/settings")).toBe(false);
            expect(isNavigationExcludedRoute("/users/preferences")).toBe(false);
            expect(isNavigationExcludedRoute("/users/organization_memberships")).toBe(false);
        });

        it("does NOT exclude /api_keys because it is a web page, not an /api/ prefix", () => {
            expect(isNavigationExcludedRoute("/api_keys")).toBe(false);
            expect(isNavigationExcludedRoute("/api_keys/")).toBe(false);
            expect(isNavigationExcludedRoute("/api_keys/new")).toBe(false);
            expect(isNavigationExcludedRoute("/api_keys/12")).toBe(false);
        });

        it("allows public informational pages", () => {
            expect(isNavigationExcludedRoute("/download")).toBe(false);
            expect(isNavigationExcludedRoute("/sms")).toBe(false);
            expect(isNavigationExcludedRoute("/privacy")).toBe(false);
            expect(isNavigationExcludedRoute("/terms")).toBe(false);
        });
    });

    describe("d) Edge cases handling", () => {
        it("handles trailing slashes on excluded and non-excluded paths", () => {
            expect(isNavigationExcludedRoute("/api/v1/")).toBe(true);
            expect(isNavigationExcludedRoute("/sessions/")).toBe(true);
            expect(isNavigationExcludedRoute("/bills/")).toBe(false);
            expect(isNavigationExcludedRoute("/legislators/")).toBe(false);
        });

        it("handles nested endpoints cleanly", () => {
            expect(isNavigationExcludedRoute("/api/v1/deeply/nested/resource/path")).toBe(true);
            expect(isNavigationExcludedRoute("/users/webauthn/sessions/0/confirm")).toBe(true);
            expect(isNavigationExcludedRoute("/admin/bill_creator/99/pipeline/nested")).toBe(false);
        });

        it("handles query strings cleanly without tripping prefix checks", () => {
            expect(isNavigationExcludedRoute("/bills?tab=all&sort=recent")).toBe(false);
            expect(isNavigationExcludedRoute("/sessions?redirect_to=%2Fbills")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/bootstrap?locale=baltimore")).toBe(true);
        });

        it("handles hash fragments cleanly", () => {
            expect(isNavigationExcludedRoute("/bills#table-header")).toBe(false);
            expect(isNavigationExcludedRoute("/sessions#oauth-token")).toBe(true);
            expect(isNavigationExcludedRoute("/api/v1/sessions#fragment")).toBe(true);
        });

        it("handles full URLs with protocol and host", () => {
            expect(isNavigationExcludedRoute("https://sway.vote/api/v1/bootstrap?foo=bar#baz")).toBe(true);
            expect(isNavigationExcludedRoute("http://localhost:3333/bills?search=crime#first")).toBe(false);
            expect(isNavigationExcludedRoute("https://sway.vote/users/webauthn/sessions")).toBe(true);
        });

        it("handles empty and falsy input safely", () => {
            expect(isNavigationExcludedRoute("")).toBe(false);
            expect(isNavigationExcludedRoute("   ")).toBe(false);
            expect(isNavigationExcludedRoute(null as unknown as string)).toBe(false);
            expect(isNavigationExcludedRoute(undefined as unknown as string)).toBe(false);
        });
    });
});

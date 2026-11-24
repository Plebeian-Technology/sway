import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { GENERIC_ENTRY, resolvePlaceholder } from "app/frontend/navigation/placeholderRegistry";

// @lat: [[navigation-placeholder-tracer#Why placeholderRegistry.ts imports no page component]]

const REGISTERED_ROWS: Array<{ pathname: string; shape: string; pageName: string }> = [
    { pathname: "/", shape: "home", pageName: "Home" },
    { pathname: "/feed", shape: "list", pageName: "Feed" },
    { pathname: "/bills", shape: "list", pageName: "All Bills" },
    { pathname: "/past_bills_of_the_month", shape: "list", pageName: "Past Bills of the Month" },
    { pathname: "/bills/12", shape: "detail", pageName: "Bill" },
    { pathname: "/bill_of_the_month", shape: "detail", pageName: "Bill of the Month" },
    { pathname: "/legislators", shape: "list", pageName: "Representatives" },
    { pathname: "/legislators/7", shape: "detail", pageName: "Representative" },
    { pathname: "/influence", shape: "dashboard", pageName: "Your Sway" },
    { pathname: "/notifications", shape: "list", pageName: "Notifications" },
    { pathname: "/api_keys", shape: "list", pageName: "API keys" },
    { pathname: "/sway_registration", shape: "form", pageName: "Registration" },
    { pathname: "/version", shape: "document", pageName: "Version" },
    { pathname: "/licenses", shape: "document", pageName: "Licenses" },
    { pathname: "/public/organizations", shape: "list", pageName: "Organizations" },
    { pathname: "/public/organizations/3", shape: "detail", pageName: "Organization" },
    { pathname: "/users/organization_memberships", shape: "list", pageName: "Your organizations" },
    { pathname: "/users/passkeys", shape: "list", pageName: "Passkeys" },
    { pathname: "/profile", shape: "list", pageName: "Profile" },
    { pathname: "/organizations/5/memberships/9", shape: "detail", pageName: "Organization membership" },
    { pathname: "/organizations/5/positions/new", shape: "form", pageName: "New position" },
    {
        pathname: "/organizations/5/membership_invites/8/confirm_accept",
        shape: "form",
        pageName: "Organization invite",
    },
    { pathname: "/admin", shape: "dashboard", pageName: "Admin" },
    { pathname: "/admin/locales", shape: "settings", pageName: "Locales" },
    { pathname: "/admin/llm_settings", shape: "settings", pageName: "Model settings" },
    { pathname: "/admin/categories", shape: "settings", pageName: "Categories" },
    { pathname: "/admin/system_prompts", shape: "document", pageName: "System prompts" },
    { pathname: "/admin/bill_creator/new", shape: "creator", pageName: "Bill Creator" },
    { pathname: "/admin/bill_creator/42/creator", shape: "creator", pageName: "Bill Creator" },
    { pathname: "/admin/bill_creator/42/schedule", shape: "creator", pageName: "Bill Creator" },
    { pathname: "/admin/bill_creator/42/pipeline", shape: "creator", pageName: "Bill Creator" },
    { pathname: "/admin/bill_creator/42/summary", shape: "creator", pageName: "Bill Creator" },
    { pathname: "/admin/bill_summary_reports", shape: "list", pageName: "Bill summary reports" },
    { pathname: "/admin/partner_reports", shape: "dashboard", pageName: "Partner reports" },
    { pathname: "/admin/registration_funnel", shape: "dashboard", pageName: "Registration funnel" },
    { pathname: "/admin/user_address_changes", shape: "list", pageName: "Address changes" },
    { pathname: "/pipeline_runs", shape: "list", pageName: "Pipeline runs" },
];

const UNREGISTERED_PATHS = ["/nowhere", "/bills/12/extra", "", "/admin/bill_creator/42/nope"];

// @lat: [[navigation-placeholder-tracer#Why the test enumerates one URL per Pages constant, in its own table]]
const PAGE_CONSTANT_URLS: Array<{ constant: string; pathname: string }> = [
    { constant: "ADMIN_BILL_SUMMARY_REPORTS", pathname: "/admin/bill_summary_reports" },
    { constant: "ADMIN_CATEGORIES", pathname: "/admin/categories" },
    { constant: "ADMIN_INDEX", pathname: "/admin" },
    { constant: "ADMIN_LLM_SETTINGS", pathname: "/admin/llm_settings" },
    { constant: "ADMIN_LOCALES", pathname: "/admin/locales" },
    { constant: "ADMIN_PARTNER_REPORTS", pathname: "/admin/partner_reports" },
    { constant: "ADMIN_PIPELINE_RUNS", pathname: "/pipeline_runs" },
    { constant: "ADMIN_REGISTRATION_FUNNEL", pathname: "/admin/registration_funnel" },
    { constant: "ADMIN_SHARED_ADDRESSES", pathname: "/admin/shared_addresses" },
    { constant: "ADMIN_SYSTEM_PROMPTS", pathname: "/admin/system_prompts" },
    { constant: "ADMIN_USER_ADDRESS_CHANGES", pathname: "/admin/user_address_changes" },
    { constant: "API_KEYS", pathname: "/api_keys" },
    { constant: "BILL", pathname: "/bills/42" },
    { constant: "BILLS", pathname: "/bills" },
    { constant: "BILL_CREATOR", pathname: "/admin/bill_creator/new" },
    { constant: "BILL_OF_THE_MONTH", pathname: "/bill_of_the_month" },
    { constant: "FEED", pathname: "/feed" },
    { constant: "HOME", pathname: "/" },
    { constant: "INFLUENCE", pathname: "/influence" },
    { constant: "LEGISLATOR", pathname: "/legislators/7" },
    { constant: "LEGISLATORS", pathname: "/legislators" },
    { constant: "LICENSES", pathname: "/licenses" },
    { constant: "NOTIFICATIONS", pathname: "/notifications" },
    { constant: "ORGANIZATION", pathname: "/public/organizations/3" },
    { constant: "ORGANIZATIONS", pathname: "/public/organizations" },
    { constant: "PASSKEY_MANAGEMENT", pathname: "/users/passkeys" },
    { constant: "PROFILE", pathname: "/profile" },
    { constant: "REGISTRATION", pathname: "/sway_registration" },
    { constant: "VERSION", pathname: "/version" },
    { constant: "USER_ORGANIZATION_MEMBERSHIPS", pathname: "/users/organization_memberships" },
    { constant: "USER_ORGANIZATION_MEMBERSHIP", pathname: "/organizations/5/memberships/9" },
    { constant: "NEW_USER_ORGANIZATION_POSITION", pathname: "/organizations/5/positions/new" },
    { constant: "ORGANIZATION_INVITE_CONFIRM", pathname: "/organizations/5/membership_invites/8/confirm_accept" },
];

// Pages served by the public.html.erb / public.tsx shell, which has no PageBodySlot.
const SHELL_EXEMPT_CONSTANTS = ["EMBED_BILL", "PRIVACY", "SMS", "TERMS"];

const PAGES_RB = resolve(__dirname, "../../../controllers/concerns/pages.rb");

const pagesRbConstants = (): string[] =>
    Array.from(readFileSync(PAGES_RB, "utf8").matchAll(/^ {2}([A-Z][A-Z0-9_]*)\s*=/gm), (m) => m[1]).sort();

describe("resolvePlaceholder", () => {
    it.each(REGISTERED_ROWS)(
        "resolves $pathname to the $shape shape named $pageName",
        ({ pathname, shape, pageName }) => {
            expect(resolvePlaceholder(pathname)).toEqual({ shape, pageName });
        },
    );

    it.each(UNREGISTERED_PATHS)("falls back to the generic entry for %s", (pathname) => {
        expect(resolvePlaceholder(pathname)).toEqual(GENERIC_ENTRY);
    });

    it("resolves a trailing slash the same as the path without it", () => {
        expect(resolvePlaceholder("/bills/")).toEqual(resolvePlaceholder("/bills"));
        expect(resolvePlaceholder("/admin/locales/")).toEqual(resolvePlaceholder("/admin/locales"));
    });

    it("does not swallow /admin/locales under /admin", () => {
        expect(resolvePlaceholder("/admin/locales").shape).toBe("settings");
        expect(resolvePlaceholder("/admin").shape).toBe("dashboard");
    });

    it("does not swallow /bills/12 under /bills", () => {
        expect(resolvePlaceholder("/bills/12").shape).toBe("detail");
        expect(resolvePlaceholder("/bills").shape).toBe("list");
    });

    it("covers every Pages constant with either a URL row or a shell exemption", () => {
        const covered = [...PAGE_CONSTANT_URLS.map((row) => row.constant), ...SHELL_EXEMPT_CONSTANTS].sort();

        expect(covered).toEqual(pagesRbConstants());
    });

    it.each(PAGE_CONSTANT_URLS)("resolves $constant ($pathname) to a named shape, never generic", ({ pathname }) => {
        expect(resolvePlaceholder(pathname).shape).not.toBe("generic");
    });
});

import { describe, expect, it, vi } from "vitest";

import { resolvePageLoader, type InertiaPageLoader } from "app/frontend/pageResolver";

describe("resolvePageLoader", () => {
    it("resolves V2 pages by page name", () => {
        const v2Loader = vi.fn<InertiaPageLoader>();

        const resolved = resolvePageLoader("Notifications", {
            "../pages/Notifications.tsx": v2Loader,
        });

        expect(resolved).toEqual({ loader: v2Loader, pageName: "Notifications" });
    });

    it("resolves nested V2 page paths", () => {
        const v2Loader = vi.fn<InertiaPageLoader>();

        const resolved = resolvePageLoader("organizations/UserOrganizationMembershipsList", {
            "../pages/organizations/UserOrganizationMembershipsList.tsx": v2Loader,
        });

        expect(resolved).toEqual({
            loader: v2Loader,
            pageName: "organizations/UserOrganizationMembershipsList",
        });
    });

    it("defaults blank page names to Home", () => {
        const homeLoader = vi.fn<InertiaPageLoader>();

        const resolved = resolvePageLoader("", { "../pages/Home.tsx": homeLoader });

        expect(resolved).toEqual({ loader: homeLoader, pageName: "Home" });
    });

    it("throws when no page exists for the requested name", () => {
        expect(() => resolvePageLoader("MissingPage", {})).toThrow('Unable to resolve Inertia page "MissingPage".');
    });
});

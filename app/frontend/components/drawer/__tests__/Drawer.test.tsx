// isActivePrefix branches (empty/root prefix, trailing-slash normalization) have no current NavItem
// call site — a regression there would pass every AuthLayout-only test. These check the helper directly.

import { cleanup, render, screen } from "@testing-library/react";
import { Bookmark } from "lucide-react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

const page = vi.hoisted(() => ({ url: "/current" }));

vi.mock("@inertiajs/react", async (importActual) => ({
    ...(await importActual<typeof import("@inertiajs/react")>()),
    usePage: () => ({ url: page.url, props: {} }),
    Link: ({
        href,
        className,
        children,
        prefetch,
        cacheFor,
        viewTransition,
        ...rest
    }: React.PropsWithChildren<{
        href?: string;
        className?: string;
        prefetch?: string | boolean;
        cacheFor?: string | string[];
        viewTransition?: boolean;
    }>) => (
        <a
            href={href}
            className={className}
            data-prefetch={prefetch === undefined ? undefined : String(prefetch)}
            data-cache-for={Array.isArray(cacheFor) ? cacheFor.join(",") : cacheFor}
            data-view-transition={viewTransition ? "true" : undefined}
            {...(rest as object)}
        >
            {children}
        </a>
    ),
}));

import Drawer, { isActivePrefix, type NavItem } from "app/frontend/components/drawer/Drawer";
import { PREFETCH_CACHE_FOR } from "app/frontend/sway_constants";

describe("Drawer.isActivePrefix — boundary + normalization", () => {
    it("returns true for an exact-match path", () => {
        expect(isActivePrefix("/admin/bill_creator", "/admin/bill_creator")).toBe(true);
    });

    it("returns true for a deeper sub-path under the prefix", () => {
        expect(isActivePrefix("/admin/bill_creator/42/edit", "/admin/bill_creator")).toBe(true);
        expect(isActivePrefix("/admin/bill_creator/new", "/admin/bill_creator")).toBe(true);
    });

    it("rejects a sibling namespace sharing the prefix substring (F-i2-WR-004 boundary lock)", () => {
        expect(isActivePrefix("/admin/bill_creator_archive", "/admin/bill_creator")).toBe(false);
    });

    it("normalizes a trailing slash on the author-supplied prefix (F-i3-IN-002)", () => {
        expect(isActivePrefix("/admin/bill_creator/new", "/admin/bill_creator/")).toBe(true);
        expect(isActivePrefix("/admin/bill_creator", "/admin/bill_creator/")).toBe(true);
        expect(isActivePrefix("/admin/bill_creator_archive", "/admin/bill_creator/")).toBe(false);
    });

    it("rejects an empty prefix entirely (F-i4-IN-001) — would otherwise match every path", () => {
        expect(isActivePrefix("/admin/bill_creator", "")).toBe(false);
        expect(isActivePrefix("/", "")).toBe(false);
        expect(isActivePrefix("/anything", "")).toBe(false);
    });

    it("rejects a root-only prefix '/' (F-i4-IN-001) — would otherwise match every path", () => {
        expect(isActivePrefix("/admin/bill_creator", "/")).toBe(false);
        expect(isActivePrefix("/anything", "/")).toBe(false);
    });

    it("returns false for an unrelated path", () => {
        expect(isActivePrefix("/legislators", "/admin/bill_creator")).toBe(false);
        expect(isActivePrefix("/admin/llm_settings", "/admin/bill_creator")).toBe(false);
    });
});

const warmedItem: NavItem = { route: "/legislators", label: "Representatives", Icon: Bookmark, prefetch: true };
const coldItem: NavItem = { route: "/bill_of_the_month", label: "Bill of the Month", Icon: Bookmark };
const externalItem: NavItem = { route: "https://github.com/sway", label: "GitHub", Icon: Bookmark, external: true };

afterEach(() => {
    cleanup();
    page.url = "/current";
});

describe("Drawer — hover prefetch and crossfade on nav items", () => {
    it("warms an item whose prefetch flag is set, and leaves one without it cold", () => {
        render(<Drawer isLoading={false} primaryItems={[warmedItem, coldItem]} secondaryItems={[]} />);

        expect(screen.getByRole("link", { name: "Representatives" })).toHaveAttribute("data-prefetch", "hover");
        expect(screen.getByRole("link", { name: "Bill of the Month" })).not.toHaveAttribute("data-prefetch");
    });

    it("requests the crossfade on every nav item regardless of its prefetch flag", () => {
        render(<Drawer isLoading={false} primaryItems={[warmedItem, coldItem]} secondaryItems={[]} />);

        expect(screen.getByRole("link", { name: "Representatives" })).toHaveAttribute("data-view-transition", "true");
        expect(screen.getByRole("link", { name: "Bill of the Month" })).toHaveAttribute("data-view-transition", "true");
    });

    it("warms and crossfades the brand link, which is a first-class way to reach Home", () => {
        render(<Drawer isLoading={false} primaryItems={[warmedItem]} secondaryItems={[]} />);

        const brand = screen.getAllByRole("link").find((link) => link.getAttribute("href") === "/");
        expect(brand).toBeDefined();
        expect(brand).toHaveAttribute("data-view-transition", "true");
        expect(brand).toHaveAttribute("data-prefetch", "hover");
    });

    it("states the shared prefetch cache window on the nav item and the brand link", () => {
        render(<Drawer isLoading={false} primaryItems={[warmedItem]} secondaryItems={[]} />);

        expect(screen.getByRole("link", { name: "Representatives" })).toHaveAttribute(
            "data-cache-for",
            PREFETCH_CACHE_FOR.join(","),
        );

        const brand = screen.getAllByRole("link").find((link) => link.getAttribute("href") === "/");
        expect(brand).toHaveAttribute("data-cache-for", PREFETCH_CACHE_FOR.join(","));
    });

    it("renders an external item as a plain anchor, neither warmed nor crossfading", () => {
        render(<Drawer isLoading={false} primaryItems={[externalItem]} secondaryItems={[]} />);

        const link = screen.getByRole("link", { name: "GitHub" });
        expect(link).not.toHaveAttribute("data-prefetch");
        expect(link).not.toHaveAttribute("data-view-transition");
        expect(link).toHaveAttribute("target", "_blank");
    });
});

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
describe("Drawer — nav trigger touch target", () => {
    it("the hamburger uses size=icon, sized size-11 below sm and size-9 at sm and up", () => {
        render(<Drawer isLoading={false} primaryItems={[warmedItem]} secondaryItems={[]} />);

        const trigger = screen.getByRole("button", { name: "Open navigation drawer" });
        expect(trigger.className).toContain("size-11");
        expect(trigger.className).toContain("sm:size-9");
    });
});

// @lat: [[drawer-header-and-nav-selection#Where the mobile header's page name comes from]]
describe("Drawer — the mobile header names the page", () => {
    const navItems: NavItem[] = [
        { route: "/legislators", label: "Representatives", Icon: Bookmark },
        { route: "/influence", label: "Your Sway", Icon: Bookmark },
    ];

    it("shows the selected nav item's label on a page the nav leads to", () => {
        page.url = "/influence";
        render(<Drawer isLoading={false} primaryItems={navItems} secondaryItems={[]} />);

        expect(screen.getByTestId("drawer-page-title").textContent).toBe("Your Sway");
    });

    it("keeps the label through a query string, which the selection rule strips", () => {
        page.url = "/legislators?tab=history";
        render(<Drawer isLoading={false} primaryItems={navItems} secondaryItems={[]} />);

        expect(screen.getByTestId("drawer-page-title").textContent).toBe("Representatives");
    });

    it("names a page outside the nav from the placeholder registry", () => {
        page.url = "/bills/42";
        render(<Drawer isLoading={false} primaryItems={navItems} secondaryItems={[]} />);

        expect(screen.getByTestId("drawer-page-title").textContent).toBe("Bill");
    });

    it("falls back to Sway on an address no entry names, rather than an empty line", () => {
        page.url = "/some/unmapped/route";
        render(<Drawer isLoading={false} primaryItems={navItems} secondaryItems={[]} />);

        expect(screen.getByTestId("drawer-page-title").textContent).toBe("Sway");
    });

    it("never shows the component's own name", () => {
        page.url = "/legislators";
        render(<Drawer isLoading={false} primaryItems={navItems} secondaryItems={[]} />);

        expect(screen.queryByText("Drawer Navigation")).toBeNull();
    });
});

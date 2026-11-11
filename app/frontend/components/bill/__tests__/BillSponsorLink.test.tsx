import { readFileSync } from "fs";
import { resolve } from "path";

import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", async (importActual) => ({
    ...(await importActual<typeof import("@inertiajs/react")>()),
    Link: ({
        href,
        className,
        children,
        prefetch,
        cacheFor,
        viewTransition,
        ...rest
    }: React.PropsWithChildren<{
        href: string;
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

import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import { PREFETCH_CACHE_FOR } from "app/frontend/sway_constants";

const BILL_DIR = resolve(__dirname, "..");

const SPONSOR_LINK_CALL_SITES = [
    "BillHeader.tsx",
    "layouts/BallotBillLayout.tsx",
    "layouts/BannerBillLayout.tsx",
    "layouts/CornerstoreBillLayout.tsx",
];

afterEach(() => {
    cleanup();
});

describe("BillSponsorLink", () => {
    it("resolves the legislator path for a numeric id", () => {
        render(<BillSponsorLink legislatorId={3}>Zeke Cohen</BillSponsorLink>);

        expect(screen.getByRole("link", { name: "Zeke Cohen" })).toHaveAttribute("href", "/legislators/3");
    });

    it("resolves the legislator path for a string id", () => {
        render(<BillSponsorLink legislatorId="3">Zeke Cohen</BillSponsorLink>);

        expect(screen.getByRole("link", { name: "Zeke Cohen" })).toHaveAttribute("href", "/legislators/3");
    });

    it("passes the caller's class name through unchanged", () => {
        render(
            <BillSponsorLink legislatorId={3} className="cs-sponsor">
                Zeke Cohen
            </BillSponsorLink>,
        );

        expect(screen.getByRole("link", { name: "Zeke Cohen" })).toHaveClass("cs-sponsor");
    });

    it("renders its children unchanged", () => {
        render(
            <BillSponsorLink legislatorId={3}>
                <b>Zeke Cohen</b>
            </BillSponsorLink>,
        );

        expect(screen.getByText("Zeke Cohen").tagName).toBe("B");
    });

    it("warms the link on hover and requests the crossfade", () => {
        render(<BillSponsorLink legislatorId={3}>Zeke Cohen</BillSponsorLink>);

        const link = screen.getByRole("link", { name: "Zeke Cohen" });
        expect(link).toHaveAttribute("data-prefetch", "hover");
        expect(link).toHaveAttribute("data-view-transition", "true");
    });

    it("states the shared prefetch cache window rather than inheriting the library default", () => {
        render(<BillSponsorLink legislatorId={3}>Zeke Cohen</BillSponsorLink>);

        expect(screen.getByRole("link", { name: "Zeke Cohen" })).toHaveAttribute(
            "data-cache-for",
            PREFETCH_CACHE_FOR.join(","),
        );
    });

    it.each(SPONSOR_LINK_CALL_SITES)("%s reaches the legislator only through this component", (fileName) => {
        const source = readFileSync(resolve(BILL_DIR, fileName), "utf8");

        expect(source).toContain("BillSponsorLink");
        expect(source).not.toMatch(/\/legislators\//);
        expect(source).not.toMatch(/ROUTES\.legislator\b/);
    });
});

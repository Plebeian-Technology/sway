import { readFileSync } from "fs";

import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

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

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<(message: unknown) => Promise<boolean>>(),
}));

import MembershipCard from "app/frontend/components/organizations/MembershipCard";
import PendingChangeCard from "app/frontend/components/organizations/PendingChangeCard";
import PositionCard from "app/frontend/components/organizations/PositionCard";
import OrganizationCard from "app/frontend/components/organizations/OrganizationCard";
import { PREFETCH_CACHE_FOR } from "app/frontend/sway_constants";

const ORGANIZATION = {
    id: 11,
    name: "Baltimore Tenants Union",
    follower_count: 4,
    icon_url: null,
} as unknown as sway.IPublicOrganization;

const MEMBERSHIP = {
    id: 5,
    role: "admin",
    positions_count: 2,
    pending_changes_count: 1,
    organization: ORGANIZATION,
} as unknown as sway.IOrganizationMembership;

const POSITION = {
    id: 3,
    support: "For",
    summary: "Backs the bill.",
    locked: false,
    bill_id: 21,
    bill: { id: 21, external_id: "25-0001", title: "An act about budgets" },
};

const PENDING_CHANGE = {
    id: 9,
    organization_bill_position_id: 3,
    support: "Against",
    summary: "Now opposes it.",
    approved_by_id: null,
};

afterEach(() => {
    cleanup();
});

describe("organization links warm their destination", () => {
    it("warms both of an organization card's links, on one address", () => {
        render(<OrganizationCard organization={ORGANIZATION} />);

        const links = screen.getAllByRole("link");
        expect(links).toHaveLength(2);

        for (const link of links) {
            expect(link).toHaveAttribute("href", "/public/organizations/11");
            expect(link).toHaveAttribute("data-prefetch", "click");
            expect(link).toHaveAttribute("data-cache-for", PREFETCH_CACHE_FOR.join(","));
        }
    });

    it("warms a membership card's link to the organization", () => {
        render(<MembershipCard membership={MEMBERSHIP} />);

        const link = screen.getByRole("link");
        expect(link).toHaveAttribute("href", "/organizations/11/memberships/5");
        expect(link).toHaveAttribute("data-prefetch", "click");
        expect(link).toHaveAttribute("data-cache-for", PREFETCH_CACHE_FOR.join(","));
    });

    it("sends the organization page's View bill link through BillRowLink", () => {
        const source = readFileSync("app/frontend/pages/Organization.tsx", "utf8");

        expect(source).toContain("BillRowLink");
        expect(source).not.toMatch(/ROUTES\.bill\(/);
    });
});

describe("the membership page's bill links", () => {
    it("warms the bill a position card names", () => {
        render(<PositionCard position={POSITION as never} organizationId={11} isAdmin={false} />);

        const link = screen.getByRole("link");
        expect(link).toHaveAttribute("href", "/bills/21");
        expect(link).toHaveAttribute("data-prefetch", "click");
        expect(link).toHaveAttribute("data-cache-for", PREFETCH_CACHE_FOR.join(","));
        expect(link).toHaveAttribute("data-view-transition", "true");
    });

    it("warms the bill a pending change names", () => {
        render(
            <PendingChangeCard
                change={PENDING_CHANGE as never}
                membership={{ ...MEMBERSHIP, positions: [POSITION] } as never}
                isAdmin={false}
            />,
        );

        const link = screen.getByRole("link");
        expect(link).toHaveAttribute("href", "/bills/21");
        expect(link).toHaveAttribute("data-prefetch", "click");
        expect(link).toHaveAttribute("data-cache-for", PREFETCH_CACHE_FOR.join(","));
        expect(link).toHaveAttribute("data-view-transition", "true");
    });
});

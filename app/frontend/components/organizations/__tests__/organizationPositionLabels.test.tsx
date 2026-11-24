import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { user: null } }),
    // Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
    usePoll: function usePoll() {},
    router: { get: vi.fn<() => void>(), put: vi.fn<() => void>(), delete: vi.fn<() => void>() },
    Link: ({ href, children }: { href: string; children: React.ReactNode }) => <a href={href}>{children}</a>,
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ id: 1, name: "baltimore-maryland-united_states" }, vi.fn<() => void>(), undefined],
    useSwayLocales: () => ({ sway_locales: [], options: [] }),
}));

vi.mock("app/frontend/components/bill/layouts/LazyBillSummaryMarkdown", () => ({
    default: ({ summary }: { summary: string }) => <p>{summary}</p>,
}));

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<() => Promise<boolean>>(),
}));

import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import OrganizationCard from "app/frontend/components/organizations/OrganizationCard";
import PositionCard from "app/frontend/components/organizations/PositionCard";
import Organization from "app/frontend/pages/Organization";
import Organizations from "app/frontend/pages/Organizations";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

afterEach(cleanup);

const organization = (managed_on_sway: boolean): sway.IPublicOrganization => ({
    id: 11,
    name: "Bikemore",
    sway_locale_id: 1,
    managed_on_sway,
});

const position = (
    id: number,
    source_kind: sway.IPublicOrganizationPosition["source_kind"],
): sway.IPublicOrganizationPosition => ({
    id,
    organization_id: 11,
    bill_id: 9,
    support: "FOR",
    summary: `Summary ${id}`,
    active: true,
    source_kind,
    source_url: null,
});

describe("organizations list page", () => {
    it("says where positions come from and when an organization is affiliated", () => {
        render(<Organizations organizations={[]} />);

        expect(screen.getByText(PARITY_COPY.orgs.listNotice)).toBeTruthy();
    });
});

describe("organization detail page", () => {
    it("tells the reader an unmanaged organization is not affiliated with Sway", () => {
        render(<Organization organization={organization(false)} organization_bill_positions={[]} />);

        expect(screen.getByText(PARITY_COPY.orgs.notAffiliated("Bikemore"))).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.orgs.managedOnSway("Bikemore"))).toBeNull();
    });

    it("shows the managed label instead for an organization that manages its positions", () => {
        render(<Organization organization={organization(true)} organization_bill_positions={[]} />);

        expect(screen.getByText(PARITY_COPY.orgs.managedOnSway("Bikemore"))).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.orgs.notAffiliated("Bikemore"))).toBeNull();
    });

    it("tags each position by who wrote it", () => {
        render(
            <Organization
                organization={organization(true)}
                organization_bill_positions={[
                    position(1, "organization"),
                    position(2, "news_article"),
                    position(3, "sway_admin"),
                    position(4, null),
                ]}
            />,
        );

        const tags = screen
            .getAllByTestId("public-organization-position")
            .map((card) => within(card).getByTestId("org-position-source-tag").textContent);
        expect(tags).toEqual([
            "Posted by Bikemore",
            PARITY_COPY.orgs.compiledBySway,
            PARITY_COPY.orgs.compiledBySway,
            PARITY_COPY.orgs.compiledBySway,
        ]);
    });
});

describe("organization card", () => {
    it("shows the managed label for a managed organization", () => {
        render(<OrganizationCard organization={organization(true)} />);

        expect(screen.getByText(PARITY_COPY.orgs.managedOnSway("Bikemore"))).toBeTruthy();
    });

    it("shows no managed label for an unmanaged organization", () => {
        render(<OrganizationCard organization={organization(false)} />);

        expect(screen.queryByText(PARITY_COPY.orgs.managedOnSway("Bikemore"))).toBeNull();
    });
});

describe("member position card", () => {
    const memberPosition = (source_kind: sway.IPublicOrganizationPosition["source_kind"]) =>
        ({
            ...position(5, source_kind),
            bill: { id: 9, external_id: "HB-1", title: "Test Bill" },
        }) as unknown as React.ComponentProps<typeof PositionCard>["position"];

    it("says the organization posted a position its members wrote", () => {
        render(
            <PositionCard
                position={memberPosition("organization")}
                organizationId={11}
                organizationName="Bikemore"
                isAdmin={false}
            />,
        );

        expect(screen.getByTestId("org-position-source-tag").textContent).toBe("Posted by Bikemore");
    });

    it("says Sway compiled a position from any other source", () => {
        render(
            <PositionCard
                position={memberPosition("hearing_testimony")}
                organizationId={11}
                organizationName="Bikemore"
                isAdmin={false}
            />,
        );

        expect(screen.getByTestId("org-position-source-tag").textContent).toBe(PARITY_COPY.orgs.compiledBySway);
    });
});

describe("OrgPositionSummary", () => {
    it("renders no tag without the organization name", () => {
        render(<OrgPositionSummary summary="A summary" summaryAiUnreviewed={false} />);

        expect(screen.getByText("A summary")).toBeTruthy();
        expect(screen.queryByTestId("org-position-source-tag")).toBeNull();
    });
});

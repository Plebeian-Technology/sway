import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Deferred: ({ children }: { children: React.ReactNode }) => children,
    Link: ({ children, ...props }: React.PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
    ),
    // @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
    usePage: function usePage() {
        return { props: {} };
    },
}));

import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";
import type { sway } from "sway";

afterEach(cleanup);

// Real Baltimore ordinance titles. The first dash-separated part is the
// CATEGORY; everything after it is what tells one bill apart from the next.
const REZONING = "Rezoning – 2400 Boston Street";
const RENTAL = "Rental Dwellings – Pricing Algorithm Use – Disclosure";
const NO_QUALIFIER = "A Resolution Honoring Volunteers";

describe("BillEntryTitle", () => {
    it("keeps the qualifier that distinguishes a bill from its neighbours", () => {
        render(<BillEntryTitle title={REZONING} />);

        expect(document.body.textContent).toContain("Rezoning");
        expect(document.body.textContent).toContain("2400 Boston Street");
    });

    it("keeps every later segment, not just the second", () => {
        render(<BillEntryTitle title={RENTAL} />);

        expect(document.body.textContent).toContain("Pricing Algorithm Use – Disclosure");
    });

    it("de-emphasizes only the qualifier, so the row still scans by subject", () => {
        const { container } = render(<BillEntryTitle title={REZONING} qualifierClassName="q" />);

        const qualifier = container.querySelector(".q");
        expect(qualifier?.textContent).toContain("2400 Boston Street");
        expect(qualifier?.textContent).not.toContain("Rezoning");
    });

    it("adds no separator when a title has no qualifier", () => {
        render(<BillEntryTitle title={NO_QUALIFIER} />);

        expect(document.body.textContent).toBe(NO_QUALIFIER);
    });

    it("drops the Maryland FOR-the-purpose-of boilerplate", () => {
        render(<BillEntryTitle title="Property Tax Credit FOR the purpose of altering the credit" />);

        expect(document.body.textContent).toBe("Property Tax Credit");
    });
});

// The bug this test guards against: four rows in a row all just reading
// "Rezoning" because the part that tells them apart got dropped. It affected
// every themed list at once, so this check runs against all of them —
// including the default layout, which never actually had the bug.
const LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

// @lat: [[bill-title-display]]
const WITH_CLAUSE =
    "Zoning Code – Modifications \n\nFOR the purpose of amending provisions of the Baltimore City Zoning Code " +
    "relating to variances to conform to relevant State law; making modifications to the process of granting variances;";
const WITH_CLAUSE_SHOWN = "Zoning Code — Modifications";

const bills = [
    { id: 1, external_id: "26-0205", title: REZONING, chamber: "council" },
    { id: 2, external_id: "26-0204", title: "Rezoning – 1801 Portal Street", chamber: "council" },
    { id: 3, external_id: "26-0215", title: RENTAL, chamber: "council" },
    { id: 4, external_id: "25-0006", title: WITH_CLAUSE, chamber: "council" },
] as unknown as sway.IBill[];

const baseProps: BillListLayoutProps = {
    bills,
    formattedSwayLocaleName: "Baltimore",
    localeSlug: "baltimore-maryland-united_states",
    localeOptions: [],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(id: number) => void>(),
    allCategories: [],
    selectedCategories: [],
    onToggleCategory: vi.fn<(category: string) => void>(),
    onClearCategories: vi.fn<() => void>(),
    hasMoreBills: false,
    isLoadingMoreBills: false,
    onLoadMoreBills: vi.fn<() => void>(),
    sortValue: DEFAULT_BILLS_SORT,
    onSortChange: vi.fn<(sort: string) => void>(),
    searchValue: "",
    onSearchChange: vi.fn<(search: string) => void>(),
};

describe.each(LAYOUTS)("%s bill titles", (_name, Layout) => {
    it("distinguishes two bills that share a category", () => {
        render(<Layout {...baseProps} />);

        expect(screen.getByText(/2400 Boston Street/)).toBeInTheDocument();
        expect(screen.getByText(/1801 Portal Street/)).toBeInTheDocument();
    });

    it("keeps the trailing segments of a multi-part title", () => {
        render(<Layout {...baseProps} />);

        expect(screen.getByText(/Pricing Algorithm Use/)).toBeInTheDocument();
    });

    // @lat: [[bill-entry-title-category-qualifier-split#What billEntryTitle.test.tsx checks beyond presence]]
    it("drops the clause that reads the same on almost every bill", () => {
        render(<Layout {...baseProps} />);

        expect(document.body.textContent).not.toContain("FOR the purpose of");
    });

    // @lat: [[bill-entry-title-category-qualifier-split#What billEntryTitle.test.tsx checks beyond presence]]
    it("shows the one title every other theme shows", () => {
        render(<Layout {...baseProps} />);

        expect(document.body.textContent).toContain(WITH_CLAUSE_SHOWN);
    });
});

// @lat: [[bills-controller-design#Why BillEditLink's visibility is proven from the prop, not the markup#list-layouts billEditLink test notes]]

import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const usePageMock = vi.fn<() => { props: { user?: { is_admin?: boolean } } }>(() => ({ props: { user: undefined } }));

vi.mock("@inertiajs/react", () => ({
    Deferred: ({ children }: { children: React.ReactNode }) => children,
    Link: ({ children, ...props }: React.PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
    ),
    usePage: function usePage() {
        return usePageMock();
    },
}));

import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";
import type { sway } from "sway";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    usePageMock.mockReturnValue({ props: { user: undefined } });
});

// @lat: [[bills-controller-design#Why BillEditLink's visibility is proven from the prop, not the markup#list-layouts billEditLink test notes]]
const LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

const bills = [
    { id: 1, external_id: "26-0205", title: "Rezoning – 2400 Boston Street", chamber: "council" },
    { id: 2, external_id: "26-0204", title: "Rezoning – 1801 Portal Street", chamber: "council" },
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

describe.each(LAYOUTS)("%s admin edit link", (_name, Layout) => {
    describe("when signed in as a sway admin", () => {
        beforeEach(() => {
            usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });
        });

        it("names each row's edit link with that bill's own identifier", () => {
            render(<Layout {...baseProps} />);

            // Naming each one distinctly is the whole point: a screen reader hearing
            // "Edit" twenty-four times in a row cannot tell which bill any of them opens.
            expect(screen.getByRole("link", { name: "Edit bill 26-0205" })).toBeInTheDocument();
            expect(screen.getByRole("link", { name: "Edit bill 26-0204" })).toBeInTheDocument();
        });

        it("points each row's edit link at that row's own bill", () => {
            render(<Layout {...baseProps} />);

            expect(screen.getByRole("link", { name: "Edit bill 26-0205" })).toHaveAttribute(
                "href",
                "/admin/bill_creator/1/creator",
            );
            expect(screen.getByRole("link", { name: "Edit bill 26-0204" })).toHaveAttribute(
                "href",
                "/admin/bill_creator/2/creator",
            );
        });
    });

    it("shows no edit link to a signed-in non-admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: false } } });

        render(<Layout {...baseProps} />);

        expect(screen.queryByRole("link", { name: /Edit bill/ })).not.toBeInTheDocument();
    });

    it("shows no edit link to a signed-out reader", () => {
        usePageMock.mockReturnValue({ props: { user: undefined } });

        render(<Layout {...baseProps} />);

        expect(screen.queryByRole("link", { name: /Edit bill/ })).not.toBeInTheDocument();
    });
});

import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

// @lat: [[deferred-bills-first-paint-empty-state#How the regression test mocks it]]
let deferredResolved = false;
vi.mock("@inertiajs/react", () => ({
    Deferred: ({ children, fallback }: { children: React.ReactNode; fallback: React.ReactNode }) =>
        deferredResolved ? children : fallback,
    Link: ({ children, ...props }: React.PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
    ),
    // @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
    usePage: function usePage() {
        return { props: {} };
    },
}));

const LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

const baseProps: Omit<BillListLayoutProps, "bills"> = {
    formattedSwayLocaleName: "Baltimore",
    localeSlug: "baltimore-maryland-united_states",
    localeOptions: [],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(...args: unknown[]) => void>(),
    allCategories: [],
    selectedCategories: [],
    onToggleCategory: vi.fn<(...args: unknown[]) => void>(),
    onClearCategories: vi.fn<() => void>(),
    hasMoreBills: false,
    isLoadingMoreBills: false,
    onLoadMoreBills: vi.fn<() => void>(),
    sortValue: DEFAULT_BILLS_SORT,
    onSortChange: vi.fn<(...args: unknown[]) => void>(),
    searchValue: "",
    onSearchChange: vi.fn<(term: string) => void>(),
};

afterEach(cleanup);

describe("bill list layouts — deferred first paint", () => {
    describe.each(LAYOUTS)("%s", (_name, Layout) => {
        it("shows the loading fallback with structured card skeletons and never 'No bills found' while bills is unresolved", () => {
            deferredResolved = false;
            // @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]]
            const { container } = render(<Layout {...baseProps} bills={[]} />);

            expect(screen.getByText(PARITY_COPY.bills.loading)).toBeInTheDocument();
            expect(
                screen.queryByText(PARITY_COPY.bills.noneFound(baseProps.formattedSwayLocaleName)),
            ).not.toBeInTheDocument();

            const busyContainer = container.querySelector("[aria-busy='true']");
            expect(busyContainer).toBeInTheDocument();
            expect(busyContainer).toHaveAttribute("aria-live", "polite");

            const placeholders = container.querySelectorAll(".placeholder-block");
            expect(placeholders.length).toBeGreaterThanOrEqual(6);
        });

        it("shows 'No bills found' and removes card skeletons once bills resolves empty", () => {
            deferredResolved = true;
            const { container } = render(<Layout {...baseProps} bills={[]} />);

            expect(
                screen.getByText(PARITY_COPY.bills.noneFound(baseProps.formattedSwayLocaleName)),
            ).toBeInTheDocument();
            expect(screen.queryByText(PARITY_COPY.bills.loading)).not.toBeInTheDocument();

            expect(container.querySelectorAll(".placeholder-block")).toHaveLength(0);
            expect(container.querySelector("[aria-busy='true']")).not.toBeInTheDocument();
        });
    });
});

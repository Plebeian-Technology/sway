// @lat: [[bills-category-filter#Why the layout sweep survives the shared control]]

import { readdirSync } from "node:fs";
import { resolve } from "node:path";

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";

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

// @lat: [[bills-category-filter#Why the layout sweep survives the shared control]]
const LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

const CATEGORIES = ["Police", "Health"];

const baseProps: BillListLayoutProps = {
    bills: [],
    formattedSwayLocaleName: "Baltimore",
    localeSlug: "baltimore-maryland-united_states",
    localeOptions: [],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(...args: unknown[]) => void>(),
    allCategories: CATEGORIES,
    selectedCategories: ["Police"],
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

const openFilter = () => fireEvent.click(screen.getByTestId("bills-category-filter"));

describe("bill list layouts — the category multi-select carries each layout's selection (C2-WR-05)", () => {
    describe.each(LAYOUTS)("%s", (_name, Layout) => {
        it("names the selection on the trigger", () => {
            render(<Layout {...baseProps} />);

            expect(screen.getByTestId("bills-category-filter")).toHaveTextContent("Police");
        });

        it("says all categories when no filter is in force", () => {
            render(<Layout {...baseProps} selectedCategories={[]} />);

            expect(screen.getByTestId("bills-category-filter")).toHaveTextContent("All categories");
        });

        it("checks the selected category and leaves the unselected one clear", () => {
            render(<Layout {...baseProps} />);
            openFilter();

            expect(screen.getByRole("checkbox", { name: "Police" })).toBeChecked();
            expect(screen.getByRole("checkbox", { name: "Health" })).not.toBeChecked();
        });

        it("reports the category a reader ticks", () => {
            const onToggleCategory = vi.fn<(category: string) => void>();
            render(<Layout {...baseProps} selectedCategories={[]} onToggleCategory={onToggleCategory} />);
            openFilter();

            fireEvent.click(screen.getByRole("checkbox", { name: "Health" }));

            expect(onToggleCategory).toHaveBeenCalledWith("Health");
        });

        // A one-click way back to the full list, but only once there's
        // something selected to clear.
        it("shows Clear all only once a category is selected, and it clears the selection", () => {
            const onClearCategories = vi.fn<() => void>();
            const { rerender } = render(
                <Layout {...baseProps} selectedCategories={[]} onClearCategories={onClearCategories} />,
            );
            openFilter();
            expect(screen.queryByRole("button", { name: "Clear all" })).not.toBeInTheDocument();

            rerender(<Layout {...baseProps} selectedCategories={["Police"]} onClearCategories={onClearCategories} />);
            fireEvent.click(screen.getByRole("button", { name: "Clear all" }));
            expect(onClearCategories).toHaveBeenCalledTimes(1);
        });
    });

    it("sweeps every layout that exists, not just the ones someone remembered", () => {
        const files = readdirSync(resolve(__dirname, "..")).filter((f) => /BillListLayout\.tsx$/.test(f));

        expect(files.sort()).toEqual(LAYOUTS.map(([name]) => `${name}.tsx`).sort());
    });
});

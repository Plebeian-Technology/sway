import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";

vi.mock("@inertiajs/react", () => ({
    Deferred: ({ children }: { children: React.ReactNode }) => children,
    Link: ({ children, ...props }: React.PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
    ),
    usePage: function usePage() {
        return { props: {} };
    },
}));

const baseProps: BillListLayoutProps = {
    bills: [],
    formattedSwayLocaleName: "Baltimore",
    localeSlug: "baltimore-maryland-united_states",
    localeOptions: [],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(swayLocaleId: number) => void>(),
    allCategories: ["Police"],
    selectedCategories: [],
    onToggleCategory: vi.fn<(categoryId: string | number) => void>(),
    onClearCategories: vi.fn<() => void>(),
    hasMoreBills: false,
    isLoadingMoreBills: false,
    onLoadMoreBills: vi.fn<() => void>(),
    sortValue: DEFAULT_BILLS_SORT,
    onSortChange: vi.fn<(sortValue: string) => void>(),
    searchValue: "",
    onSearchChange: vi.fn<(searchValue: string) => void>(),
};

afterEach(cleanup);

describe("DefaultBillListLayout — more-options disclosure", () => {
    // @lat: [[bills-filter-header#Why sort and categories collapse only on mobile]]
    it("keeps sort and categories mounted while collapsed, and toggles aria-expanded", () => {
        render(<DefaultBillListLayout {...baseProps} />);

        const trigger = screen.getByTestId("btn-bills-more-options");
        const panel = document.getElementById("v2-bills-more-options");

        expect(trigger).toHaveAttribute("aria-controls", "v2-bills-more-options");
        expect(trigger).toHaveAttribute("aria-expanded", "false");

        expect(panel).not.toBeNull();
        expect(panel?.className).toContain("hidden");
        expect(screen.getByLabelText(/sort/i)).toBeInTheDocument();

        fireEvent.click(trigger);

        expect(trigger).toHaveAttribute("aria-expanded", "true");
        expect(document.getElementById("v2-bills-more-options")?.className).not.toContain("hidden");
    });

    // @lat: [[bills-filter-header#Why the fields are ordered twice]]
    it("renders locale and search ahead of the disclosure so mobile leads with them", () => {
        const { container } = render(<DefaultBillListLayout {...baseProps} />);

        const ids = Array.from(container.querySelectorAll("#v2-bills-locale, #v2-bills-search")).map((el) => el.id);
        const trigger = screen.getByTestId("btn-bills-more-options");

        expect(ids).toEqual(["v2-bills-locale", "v2-bills-search"]);
        expect(trigger.compareDocumentPosition(container.querySelector("#v2-bills-search") as Node)).toBe(
            Node.DOCUMENT_POSITION_PRECEDING,
        );
    });
});

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { BILLS_SORT_OPTIONS } from "app/frontend/components/bill/list-layouts/types";
import { LAYOUTS, baseProps } from "./harness";

// @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#How much of the list is shown lives in the URL too]]
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

afterEach(cleanup);

describe("bill list layouts — sort select", () => {
    describe.each(LAYOUTS)("%s", (_name, Layout) => {
        it("renders every shared sort option with the current selection", () => {
            render(<Layout {...baseProps} sortValue="title:asc" />);

            const select = screen.getByTestId("select-sort-bills") as HTMLSelectElement;
            expect(select.value).toBe("title:asc");
            expect(select.options).toHaveLength(BILLS_SORT_OPTIONS.length);
            expect(Array.from(select.options).map((option) => option.value)).toEqual(
                BILLS_SORT_OPTIONS.map((option) => option.value),
            );
        });

        it("forwards a selection to onSortChange", () => {
            const onSortChange = vi.fn<(sortValue: string) => void>();
            render(<Layout {...baseProps} onSortChange={onSortChange} />);

            fireEvent.change(screen.getByTestId("select-sort-bills"), { target: { value: "title:desc" } });

            expect(onSortChange).toHaveBeenCalledTimes(1);
            expect(onSortChange).toHaveBeenCalledWith("title:desc");
        });
    });
});

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { BILLS_SEARCH_PLACEHOLDER } from "app/frontend/components/bill/list-layouts/types";
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

describe("bill list layouts — search input", () => {
    describe.each(LAYOUTS)("%s", (_name, Layout) => {
        it("renders the shared search input with the current value", () => {
            render(<Layout {...baseProps} searchValue="police" />);

            const input = screen.getByTestId("input-search-bills") as HTMLInputElement;
            expect(input.value).toBe("police");
            expect(input.placeholder).toBe(BILLS_SEARCH_PLACEHOLDER);
            expect(input.type).toBe("search");
        });

        it("forwards each keystroke's term to onSearchChange", () => {
            const onSearchChange = vi.fn<(term: string) => void>();
            render(<Layout {...baseProps} onSearchChange={onSearchChange} />);

            fireEvent.change(screen.getByTestId("input-search-bills"), { target: { value: "housing" } });

            expect(onSearchChange).toHaveBeenCalledTimes(1);
            expect(onSearchChange).toHaveBeenCalledWith("housing");
        });
    });
});

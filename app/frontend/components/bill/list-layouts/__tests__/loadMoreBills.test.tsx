import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { BILLS_LOAD_MORE_LABEL, BILLS_LOADING_MORE_LABEL } from "app/frontend/components/bill/list-layouts/types";
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

describe("bill list layouts — load more window", () => {
    describe.each(LAYOUTS)("%s", (_name, Layout) => {
        it("renders no load-more control when the window already holds every bill", () => {
            render(<Layout {...baseProps} hasMoreBills={false} />);

            expect(screen.queryByTestId("btn-load-more-bills")).not.toBeInTheDocument();
        });

        it("renders the load-more control and forwards clicks when more bills exist", () => {
            const onLoadMoreBills = vi.fn<() => void>();
            render(<Layout {...baseProps} hasMoreBills={true} onLoadMoreBills={onLoadMoreBills} />);

            const button = screen.getByTestId("btn-load-more-bills");
            expect(button).toHaveTextContent(BILLS_LOAD_MORE_LABEL);

            fireEvent.click(button);
            expect(onLoadMoreBills).toHaveBeenCalledTimes(1);
        });

        it("disables the control and shows loading copy while the next page is in flight", () => {
            render(<Layout {...baseProps} hasMoreBills={true} isLoadingMoreBills={true} />);

            const button = screen.getByTestId("btn-load-more-bills");
            expect(button).toBeDisabled();
            expect(button).toHaveTextContent(BILLS_LOADING_MORE_LABEL);
        });
    });
});

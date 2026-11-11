// @lat: [[bills-controller-design#Why BillEditLink's visibility is proven from the prop, not the markup]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PropsWithChildren } from "react";
import type { sway } from "sway";

const usePageMock = vi.fn<() => { props: { user?: Partial<sway.IUser> } }>(() => ({ props: { user: undefined } }));

vi.mock("@inertiajs/react", () => ({
    usePage: function usePage() {
        return usePageMock();
    },
    Link: ({ children, ...props }: PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
    ),
}));

import BillEditLink from "app/frontend/components/bill/BillEditLink";
import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    usePageMock.mockReturnValue({ props: { user: undefined } });
});

describe("BillEditLink — visibility", () => {
    it("renders for a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        render(<BillEditLink billId={7} billIdentifier="26-0205" />);

        expect(screen.getByRole("link")).toBeInTheDocument();
    });

    it("renders nothing for a signed-in non-admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: false } } });

        const { container } = render(<BillEditLink billId={7} billIdentifier="26-0205" />);

        expect(container).toBeEmptyDOMElement();
    });

    it("renders nothing for a signed-out reader", () => {
        usePageMock.mockReturnValue({ props: { user: undefined } });

        const { container } = render(<BillEditLink billId={7} billIdentifier="26-0205" />);

        expect(container).toBeEmptyDOMElement();
    });

    // @lat: [[bills-controller-design#Why BillEditLink's visibility is proven from the prop, not the markup]]
    it("does not treat an unrelated truthy admin-shaped field as a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: false, isAdmin: true } as Partial<sway.IUser> } });

        const { container } = render(<BillEditLink billId={7} billIdentifier="26-0205" />);

        expect(container).toBeEmptyDOMElement();
    });

    it("renders nothing for an archived historical bill even when signed in as a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        const { container } = render(
            <BillEditLink
                billId={7}
                billIdentifier="26-0205"
                isArchived={isArchivedHistoricalBill({ active: false, scheduled_release_date_utc: null })}
            />,
        );

        expect(container).toBeEmptyDOMElement();
    });

    it("renders for an unarchived Past Bill of the Month from a prior session when signed in as a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        render(
            <BillEditLink
                billId={7}
                billIdentifier="24-0101"
                isArchived={isArchivedHistoricalBill({ active: false, scheduled_release_date_utc: "2024-05-01" })}
            />,
        );

        expect(screen.getByRole("link")).toBeInTheDocument();
    });
});

describe("BillEditLink — destination and accessible name", () => {
    beforeEach(() => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });
    });

    it("points at the canonical bill-creator edit address, not the legacy redirect", () => {
        render(<BillEditLink billId={42} billIdentifier="26-0205" />);

        expect(screen.getByRole("link")).toHaveAttribute("href", "/admin/bill_creator/42/creator");
    });

    it("names the specific bill in a row's accessible name, so many rows read as many different controls", () => {
        render(<BillEditLink billId={1} billIdentifier="26-0205" variant="row" />);

        expect(screen.getByRole("link", { name: "Edit bill 26-0205" })).toBeInTheDocument();
    });

    it("shows the visible sentence-case label on the bill detail page", () => {
        render(<BillEditLink billId={1} billIdentifier="26-0205" variant="detail" />);

        expect(screen.getByRole("link", { name: "Edit bill" })).toBeInTheDocument();
    });
});

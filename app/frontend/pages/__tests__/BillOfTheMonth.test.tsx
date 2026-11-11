// @lat: [[client-caches-and-identity#Bill refresh feedback]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PropsWithChildren } from "react";
import type { sway } from "sway";

const usePollMock =
    vi.fn<(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);
const usePageMock = vi.fn<() => { props: { user?: Partial<sway.IUser> } }>(() => ({ props: { user: undefined } }));

vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) {
        usePollMock(interval, options, pollOptions);
    },
    usePage: function usePage() {
        return usePageMock();
    },
    router: { reload: vi.fn<() => void>() },
    Link: ({
        children,
        viewTransition,
        ...props
    }: PropsWithChildren<Record<string, unknown> & { viewTransition?: boolean }>) => (
        <a data-view-transition={viewTransition ? "true" : undefined} {...(props as object)}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: (only: string[]) => scoreSubscriptionMock(only),
}));
vi.mock("app/frontend/hooks/useActionCableReconnect", () => ({
    useActionCableReconnect: vi.fn<() => void>(),
}));

vi.mock("app/frontend/hooks/usePullToRefresh", () => ({
    usePullToRefresh: vi.fn<() => void>(),
}));
let currentSwayLocale: { name: string } | null = null;
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [currentSwayLocale, vi.fn<(value: unknown) => void>()],
    useSwayLocales: () => ({ options: [] }),
}));

vi.mock("app/frontend/components/bill/BillHeader", () => ({
    default: () => <div data-testid="bill-header" />,
}));
vi.mock("app/frontend/components/bill/VotePanel", () => ({
    default: () => <div data-testid="vote-panel" />,
}));
vi.mock("app/frontend/components/bill/BillContent", () => ({
    default: () => <div data-testid="bill-content" />,
}));

import BillOfTheMonth from "app/frontend/pages/BillOfTheMonth";

const BILL = { id: 7, external_id: "HB1" } as sway.IBill;
const SPONSOR = { id: 1 } as sway.ILegislator;

afterEach(() => {
    cleanup();
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    usePageMock.mockReset();
    usePageMock.mockReturnValue({ props: { user: undefined } });
    currentSwayLocale = null;
});

describe("BillOfTheMonth — poll + score-subscription refresh contract", () => {
    it("polls every 15s and subscribes on the same tuple", () => {
        render(<BillOfTheMonth bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock.mock.calls[0][0]).toBe(15000);
        expect(usePollMock.mock.calls[0]?.[2]).toEqual({ background: "pause" });

        // @lat: [[client-caches-and-identity#Bill refresh feedback]]
        const pollOnly = usePollMock.mock.calls[0][1].only;
        const subscribedTuple = scoreSubscriptionMock.mock.calls[0][0];
        expect(pollOnly).toBe(subscribedTuple);
    });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    it("refreshes every prop it renders, because the featured bill can be re-pointed under the reader", () => {
        render(<BillOfTheMonth bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(usePollMock.mock.calls[0][1].only).toEqual([
            "bill",
            "sponsor",
            "organizations",
            "user_vote",
            "bill_score",
        ]);
    });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    it("keeps asking for the bill while the empty state is on screen", () => {
        render(<BillOfTheMonth sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(usePollMock.mock.calls[0][1].only).toContain("bill");
    });

    it("renders empty state with 'No Bill of the Month for Baltimore.' when no bill is provided", () => {
        currentSwayLocale = { name: "baltimore" };
        const { getByTestId } = render(<BillOfTheMonth sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);
        const emptyState = getByTestId("botm-empty");
        expect(emptyState.textContent).toContain("No Bill of the Month for Baltimore.");
    });
});

// @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
describe("BillOfTheMonth — admin edit link", () => {
    it("shows a labelled Edit bill link to a sway admin when a bill is featured", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        render(<BillOfTheMonth bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        const link = screen.getByRole("link", { name: "Edit bill" });
        expect(link).toHaveAttribute("href", "/admin/bill_creator/7/creator");
        expect(link).toHaveAttribute("data-view-transition", "true");
    });

    it("shows no edit link to a signed-in non-admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: false } } });

        render(<BillOfTheMonth bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(screen.queryByText("Edit bill")).not.toBeInTheDocument();
    });

    it("shows no edit link to a signed-out reader", () => {
        usePageMock.mockReturnValue({ props: { user: undefined } });

        render(<BillOfTheMonth bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(screen.queryByText("Edit bill")).not.toBeInTheDocument();
    });

    it("shows no edit link when the locale has no featured bill even for a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        render(<BillOfTheMonth sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(screen.queryByText("Edit bill")).not.toBeInTheDocument();
    });
});

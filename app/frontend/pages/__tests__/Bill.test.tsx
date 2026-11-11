// @lat: [[client-caches-and-identity#Bill refresh feedback]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PropsWithChildren } from "react";
import type { sway } from "sway";

const usePollMock =
    vi.fn<(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);
// Signed-out is the default: most cases in this file don't care about the admin edit
// link, so a test that forgets to set this up exercises the "nothing new" case, not
// an accidental admin one.
const usePageMock = vi.fn<() => { props: { user?: Partial<sway.IUser> } }>(() => ({ props: { user: undefined } }));

// Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) {
        usePollMock(interval, options, pollOptions);
    },
    usePage: function usePage() {
        return usePageMock();
    },
    router: { reload: vi.fn<(opts?: Record<string, unknown>) => void>() },
    Link: ({ children, ...props }: PropsWithChildren<Record<string, unknown>>) => (
        <a {...(props as object)}>{children}</a>
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
vi.mock("app/frontend/hooks/useActiveThemeId", () => ({
    useActiveThemeId: () => "sway",
}));

// Swap the theme layout lookup for a throwaway component, so the page renders only
// one level deep. Do NOT disturb the real registry.
vi.mock("app/frontend/components/bill/layouts", () => ({
    billLayoutFor: () => () => <div data-testid="bill-layout" />,
}));

import Bill from "app/frontend/pages/Bill";

const BILL = { id: 7, external_id: "HB1" } as sway.IBill;
const SPONSOR = { id: 1 } as sway.ILegislator;

afterEach(() => {
    cleanup();
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    usePageMock.mockReset();
    usePageMock.mockReturnValue({ props: { user: undefined } });
});

describe("Bill — poll + score-subscription refresh contract", () => {
    it("polls every 15s with only:[bill_score, organizations, user_legislator_emails] and subscribes on the same tuple", () => {
        render(<Bill bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        // The 15000 is fixed by the web-and-mobile refresh agreement. "organizations"
        // was added later, then "user_legislator_emails", so the email send statuses
        // update on their own.
        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(
            15000,
            {
                only: ["bill_score", "organizations", "user_legislator_emails"],
            },
            { background: "pause" },
        );
        expect(scoreSubscriptionMock).toHaveBeenCalledWith(["bill_score", "organizations", "user_legislator_emails"]);

        // @lat: [[poll-and-subscription-same-array-assertion#Why the poll/subscription tests check object identity]]
        const pollOnly = usePollMock.mock.calls[0][1].only;
        const subscribedTuple = scoreSubscriptionMock.mock.calls[0][0];
        expect(pollOnly).toBe(subscribedTuple);
    });
});

// @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
describe("Bill — admin edit link", () => {
    it("shows a labelled Edit bill link to a sway admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: true } } });

        render(<Bill bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        const link = screen.getByRole("link", { name: "Edit bill" });
        expect(link).toHaveAttribute("href", "/admin/bill_creator/7/creator");
    });

    it("shows no edit link to a signed-in non-admin", () => {
        usePageMock.mockReturnValue({ props: { user: { is_admin: false } } });

        render(<Bill bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(screen.queryByText("Edit bill")).not.toBeInTheDocument();
    });

    it("shows no edit link to a signed-out reader", () => {
        usePageMock.mockReturnValue({ props: { user: undefined } });

        render(<Bill bill={BILL} sponsor={SPONSOR} organizations={[]} legislator_votes={[]} />);

        expect(screen.queryByText("Edit bill")).not.toBeInTheDocument();
    });
});

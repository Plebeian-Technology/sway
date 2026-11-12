import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { IFeedItem } from "app/frontend/components/feed/types";

const infiniteScrollCalls = vi.hoisted(() => [] as Array<Record<string, unknown>>);
const routerGet = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());

vi.mock("@inertiajs/react", () => ({
    Head: ({ title }: { title?: string }) => <title>{title}</title>,
    router: {
        get: (...args: unknown[]) => routerGet(...args),
    },
    InfiniteScroll: ({
        children,
        data,
        preserveUrl,
        ...rest
    }: {
        children?: React.ReactNode;
        data: string;
        preserveUrl?: boolean;
        [key: string]: unknown;
    }) => {
        infiniteScrollCalls.push({ data, preserveUrl, ...rest });
        return (
            <div data-testid="infinite-scroll" data-prop={data} data-preserve-url={String(Boolean(preserveUrl))}>
                {children}
            </div>
        );
    },
    Link: ({ children, href, ...rest }: { children: React.ReactNode; href: string; [key: string]: unknown }) => (
        <a href={href} {...rest}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/components/bill/ShareBillButton", () => ({
    default: ({ bill }: { bill: { id: number; title: string } }) => (
        <button type="button" data-testid={`share-bill-${bill.id}`}>
            Share
        </button>
    ),
}));

import Feed from "app/frontend/pages/Feed";

const makeItem = (overrides: Partial<IFeedItem>): IFeedItem => ({
    key: "item:1",
    kind: "user_joined",
    occurred_at: "2026-11-12T15:00:00Z",
    sway_locale: null,
    bill: null,
    legislator: null,
    legislators: [],
    organization: null,
    user_support: null,
    legislator_support: null,
    agreement: null,
    ...overrides,
});

beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-12T18:00:00Z"));
    window.history.replaceState({}, "", "/feed");
    infiniteScrollCalls.length = 0;
    routerGet.mockReset();
});

afterEach(() => {
    cleanup();
    vi.useRealTimers();
});

describe("Feed page", () => {
    it("renders the empty state when there are no items", () => {
        render(<Feed items={[]} />);

        expect(
            screen.getByText(
                "Nothing here yet. New Bills of the Month and your representatives' votes will show up here.",
            ),
        ).toBeTruthy();
    });

    it("wraps items in InfiniteScroll with data='items' and preserveUrl", () => {
        render(
            <Feed
                items={[
                    makeItem({
                        key: "user_joined:1",
                        kind: "user_joined",
                        occurred_at: "2026-11-12T15:00:00Z",
                    }),
                ]}
            />,
        );

        const container = screen.getByTestId("infinite-scroll");
        expect(container.getAttribute("data-prop")).toBe("items");
        expect(container.getAttribute("data-preserve-url")).toBe("true");
        expect(infiniteScrollCalls[0]?.preserveUrl).toBe(true);
    });

    it("renders all six item kinds with expected copy", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "botm:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore City" },
                bill: {
                    id: 101,
                    external_id: "Council Bill 26-0141",
                    title: "Expanding vacant building receivership",
                    summary: "Lets the city hand more long-vacant houses to court-appointed receivers.",
                },
            }),
            makeItem({
                key: "leg_vote:1",
                kind: "legislator_voted",
                occurred_at: "2026-11-12T15:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: {
                    id: 102,
                    external_id: "SB 203",
                    title: "Statewide right to counsel",
                    summary: null,
                },
                legislator: {
                    id: 10,
                    full_name: "Jane Smith",
                    title: "State Senator",
                    district_name: "District 40",
                    photo_url: null,
                },
                legislator_support: "AGAINST",
                user_support: null,
            }),
            makeItem({
                key: "org_pos:1",
                kind: "organization_position_taken",
                occurred_at: "2026-11-11T16:15:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: {
                    id: 103,
                    external_id: "SB 88",
                    title: "Lead paint inspections",
                    summary: null,
                },
                organization: {
                    id: 5,
                    name: "Bikemore",
                    support: "Support",
                },
            }),
            makeItem({
                key: "user_joined:1",
                kind: "user_joined",
                occurred_at: "2026-11-12T10:02:00Z",
            }),
            makeItem({
                key: "reps_found:1",
                kind: "representatives_found",
                occurred_at: "2026-11-12T10:03:00Z",
                legislators: [
                    {
                        id: 10,
                        full_name: "Jane Smith",
                        title: "State Senator",
                        district_name: "District 40",
                        photo_url: null,
                    },
                ],
            }),
            makeItem({
                key: "term:1",
                kind: "legislative_term_began",
                occurred_at: "2026-01-08T00:00:00Z",
                sway_locale: { id: 3, name: "U.S. Congress" },
            }),
        ];

        render(<Feed items={items} />);

        expect(screen.getByText(/released the November Bill of the Month/)).toBeTruthy();
        expect(
            screen.getByText(
                (_, element) =>
                    element?.tagName === "P" &&
                    /Jane Smith\s+voted\s+Against\s+a Maryland bill/.test(element.textContent ?? ""),
            ),
        ).toBeTruthy();
        expect(screen.getByText(/supports a Maryland bill/)).toBeTruthy();
        expect(screen.getByText(/joined Sway/)).toBeTruthy();
        expect(screen.getByText(/found your representatives/)).toBeTruthy();
        expect(screen.getByText("See your representatives")).toBeTruthy();
        expect(screen.getByText("New legislative term for U.S. Congress!")).toBeTruthy();
    });

    it("groups items under Today, Yesterday, Earlier this month, and older month headings in sentence case", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "today:1",
                kind: "user_joined",
                occurred_at: "2026-11-12T15:00:00Z",
            }),
            makeItem({
                key: "yesterday:1",
                kind: "organization_position_taken",
                occurred_at: "2026-11-11T15:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: { id: 103, external_id: "SB 88", title: "Lead paint", summary: null },
                organization: { id: 5, name: "Bikemore", support: "Oppose" },
            }),
            makeItem({
                key: "earlier:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore City" },
                bill: { id: 101, external_id: "CB 1", title: "Nov Bill", summary: null },
            }),
            makeItem({
                key: "older:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-10-01T00:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: { id: 104, external_id: "HB 1", title: "Oct Bill", summary: null },
            }),
        ];

        render(<Feed items={items} />);

        expect(screen.getByRole("heading", { name: "Today" })).toBeTruthy();
        expect(screen.getByRole("heading", { name: "Yesterday" })).toBeTruthy();
        expect(screen.getByRole("heading", { name: "Earlier this month" })).toBeTruthy();
        expect(screen.getByRole("heading", { name: "October 2026" })).toBeTruthy();
    });

    it("renders agree and differ vote comparisons on legislator_voted when user_support is set", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "agree:1",
                kind: "legislator_voted",
                occurred_at: "2026-11-12T14:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: { id: 201, external_id: "HB 412", title: "Fare cap", summary: null },
                legislator: {
                    id: 11,
                    full_name: "Alex Delegate",
                    title: "Delegate",
                    district_name: "District 40",
                    photo_url: null,
                },
                user_support: "FOR",
                legislator_support: "FOR",
                agreement: "agree",
            }),
            makeItem({
                key: "differ:1",
                kind: "legislator_voted",
                occurred_at: "2026-11-12T13:00:00Z",
                sway_locale: { id: 3, name: "U.S. Congress" },
                bill: { id: 202, external_id: "S. 1820", title: "Rural broadband", summary: null },
                legislator: {
                    id: 12,
                    full_name: "Pat Senator",
                    title: "U.S. Senator",
                    district_name: null,
                    photo_url: null,
                },
                user_support: "FOR",
                legislator_support: "AGAINST",
                agreement: "differ",
            }),
        ];

        render(<Feed items={items} />);

        expect(screen.getByText("You agree")).toBeTruthy();
        expect(screen.getByText("You differ")).toBeTruthy();
        expect(screen.getAllByText(/voted on a bill you voted on/)).toHaveLength(2);
    });

    it("renders 'Go vote' when user_support is null and 'You voted ...' when user_support is set", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "unvoted:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore City" },
                bill: { id: 301, external_id: "CB 1", title: "Unvoted Bill", summary: null },
                user_support: null,
            }),
            makeItem({
                key: "voted:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: { id: 302, external_id: "HB 2", title: "Voted Bill", summary: null },
                user_support: "AGAINST",
            }),
        ];

        render(<Feed items={items} />);

        const goVoteLink = screen.getByRole("link", { name: "Go vote" });
        expect(goVoteLink.getAttribute("href")).toBe("/bills/301");
        expect(
            screen.getByText(
                (_, element) =>
                    element?.tagName === "SPAN" &&
                    /You voted\s+Against/.test(element.textContent ?? "") &&
                    element.className.includes("mr-auto"),
            ),
        ).toBeTruthy();
        expect(screen.getByTestId("share-bill-301")).toBeTruthy();
        expect(screen.getByTestId("share-bill-302")).toBeTruthy();
    });

    it("renders a labelled search input and debounces typing into feed_search with reset and dropped feed_cursor", () => {
        window.history.replaceState({}, "", "/feed?feed_cursor=abc123");
        render(<Feed items={[]} />);

        const input = screen.getByLabelText("Search your feed") as HTMLInputElement;
        expect(input.getAttribute("placeholder")).toBe("Search bills, places and legislators");

        fireEvent.change(input, { target: { value: "housing" } });
        expect(routerGet).not.toHaveBeenCalled();

        vi.advanceTimersByTime(400);

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url, , options] = routerGet.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("feed_search")).toBe("housing");
        expect(params.get("feed_cursor")).toBe("");
        expect(options).toMatchObject({
            only: ["items", "feed_search"],
            reset: ["items"],
        });
    });

    it("renders the clear button when searching and clears feed_search when clicked", () => {
        window.history.replaceState({}, "", "/feed?feed_search=housing&feed_cursor=abc123");
        render(
            <Feed
                items={[
                    makeItem({
                        key: "user_joined:1",
                        kind: "user_joined",
                        occurred_at: "2026-11-12T15:00:00Z",
                    }),
                ]}
                feed_search="housing"
            />,
        );

        const clearButton = screen.getByRole("button", { name: "Clear search" });
        fireEvent.click(clearButton);
        vi.advanceTimersByTime(400);

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url, , options] = routerGet.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("feed_search")).toBe("");
        expect(params.get("feed_cursor")).toBe("");
        expect(options).toMatchObject({
            only: ["items", "feed_search"],
            reset: ["items"],
        });
    });

    it("renders the match summary when feed_search has results and no-match message with all bills link when empty", () => {
        const { rerender } = render(
            <Feed
                items={[
                    makeItem({
                        key: "botm:1",
                        kind: "bill_of_the_month_released",
                        occurred_at: "2026-11-01T00:00:00Z",
                        sway_locale: { id: 1, name: "Baltimore City" },
                        bill: { id: 101, external_id: "CB 1", title: "Fare cap", summary: null },
                    }),
                    makeItem({
                        key: "botm:2",
                        kind: "bill_of_the_month_released",
                        occurred_at: "2026-11-01T00:00:00Z",
                        sway_locale: { id: 2, name: "Maryland" },
                        bill: { id: 102, external_id: "HB 2", title: "Fare equity", summary: null },
                    }),
                ]}
                feed_search="fare"
            />,
        );

        expect(screen.getByText('2 items in your feed match "fare"')).toBeTruthy();

        rerender(<Feed items={[]} feed_search="fare" />);

        expect(screen.getByText(/Nothing in your feed matches "fare"/)).toBeTruthy();
        const allBillsLink = screen.getByRole("link", { name: "all bills" });
        expect(allBillsLink.getAttribute("href")).toBe("/bills");
    });
});

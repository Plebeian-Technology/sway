import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { PendingVisit } from "@inertiajs/core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { cleanFeedSummary } from "app/frontend/components/feed/feedSummary";
import type { IFeedItem } from "app/frontend/components/feed/types";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { applyNavigationCarryToVisit } from "app/frontend/sway_utils/queryParamNavigationCarry";

const infiniteScrollCalls = vi.hoisted(() => [] as Array<Record<string, unknown>>);
const routerGet = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const routerReload = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const usePollMock = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const notifyMock = vi.hoisted(() => vi.fn<(...args: unknown[]) => string>(() => "toast-id"));
const subscriptionUnsubscribe = vi.hoisted(() => vi.fn<() => void>());
const channelCallbacks = vi.hoisted(() => ({
    current: null as { received?: (data: { type?: string }) => void } | null,
}));
const subscriptionsCreate = vi.hoisted(() =>
    vi.fn<
        (_channel: string, callbacks: { received?: (data: { type?: string }) => void }) => { unsubscribe: () => void }
    >((_channel, callbacks) => {
        channelCallbacks.current = callbacks;
        return { unsubscribe: subscriptionUnsubscribe };
    }),
);

vi.mock("app/frontend/channels/consumer", () => ({
    default: {
        subscriptions: {
            create: subscriptionsCreate,
        },
    },
}));

vi.mock("@inertiajs/react", () => ({
    Head: ({ title }: { title?: string }) => <title>{title}</title>,
    router: {
        get: (...args: unknown[]) => routerGet(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
    usePoll: (...args: unknown[]) => usePollMock(...args),
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

vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return {
        ...actual,
        notify: (...args: unknown[]) => notifyMock(...args),
    };
});

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
    notifyMock.mockClear();
});

afterEach(() => {
    cleanup();
    vi.useRealTimers();
});

describe("Feed page", () => {
    it("renders the empty state when there are no items", () => {
        render(<Feed feed_match_count={0} items={[]} />);

        expect(
            screen.getByText(
                "Nothing here yet. New Bills of the Month and your representatives' votes will show up here.",
            ),
        ).toBeTruthy();
    });

    it("wraps items in InfiniteScroll with data='items' and preserveUrl", () => {
        render(
            <Feed
                feed_match_count={0}
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

    it("renders all six item kinds with expected copy and BAL locale abbreviation", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "botm:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore" },
                bill: {
                    id: 101,
                    external_id: "Council Bill 26-0141",
                    title: "Expanding vacant building receivership",
                    summary: "Lets the city hand more long-vacant houses to court-appointed receivers.",
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
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
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
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
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
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

        render(<Feed feed_match_count={0} items={items} />);

        expect(screen.getByText("BAL")).toBeTruthy();
        expect(screen.getByText(/released the November Bill of the Month/)).toBeTruthy();
        expect(
            screen.getByText(
                (_, element) =>
                    element?.tagName === "P" &&
                    /Jane Smith\s+voted\s+Against\s+a Maryland bill/.test(element.textContent ?? ""),
            ),
        ).toBeTruthy();
        expect(screen.getByText(/Sway recorded that\s+supports a Maryland bill/)).toBeTruthy();
        expect(screen.getByText(/joined Sway/)).toBeTruthy();
        expect(screen.getByText(/found your representatives/)).toBeTruthy();
        expect(screen.getByText("See your representatives")).toBeTruthy();
        expect(screen.getByText("New legislative term for U.S. Congress!")).toBeTruthy();
    });

    it("strips 'FOR the purpose of' clauses from bill titles and cleans or omits pending/Markdown summaries", () => {
        const items: IFeedItem[] = [
            makeItem({
                key: "botm:clean",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore" },
                bill: {
                    id: 601,
                    external_id: "CB 26-0601",
                    title: "Urban Tree Canopy - Street Planting FOR the purpose of requiring tree planting along arterial streets; and generally relating to urban forestry.",
                    summary:
                        "## OverviewNEWLINERequires **Baltimore** to plant [street trees](https://example.com/trees) on *arterial* corridors.ENDING",
                    view_count: 11,
                    share_count: 1,
                    summary_ai_unreviewed: false,
                },
            }),
            makeItem({
                key: "botm:pending",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: {
                    id: 602,
                    external_id: "HB 602",
                    title: "Pending Summary Bill",
                    summary: "Summary pending",
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
            }),
        ];

        render(<Feed feed_match_count={0} items={items} />);

        expect(screen.getByText("Urban Tree Canopy — Street Planting")).toBeTruthy();
        expect(screen.queryByText(/FOR the purpose of/i)).toBeNull();
        expect(
            screen.getByText("Overview Requires Baltimore to plant street trees on arterial corridors."),
        ).toBeTruthy();
        expect(screen.queryByText(/NEWLINE|ENDING/)).toBeNull();
        expect(screen.queryByText("Summary pending")).toBeNull();
    });

    it("shows the AI unreviewed notice under a Bill of the Month summary only when summary_ai_unreviewed is true", () => {
        const makeBotm = (id: number, unreviewed: boolean): IFeedItem =>
            makeItem({
                key: `botm:${id}`,
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore" },
                bill: {
                    id,
                    external_id: `CB ${id}`,
                    title: `Bill ${id}`,
                    summary: "Funds new bus shelters.",
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: unreviewed,
                },
            });

        render(<Feed feed_match_count={0} items={[makeBotm(701, true), makeBotm(702, false)]} />);

        expect(screen.getAllByText("Funds new bus shelters.")).toHaveLength(2);
        expect(screen.getAllByTestId("ai-unreviewed-notice")).toHaveLength(1);
        expect(screen.getByText(PARITY_COPY.bill.aiUnreviewedNotice)).toBeTruthy();
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
                bill: {
                    id: 103,
                    external_id: "SB 88",
                    title: "Lead paint",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
                organization: { id: 5, name: "Bikemore", support: "Oppose" },
            }),
            makeItem({
                key: "earlier:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 1, name: "Baltimore" },
                bill: {
                    id: 101,
                    external_id: "CB 1",
                    title: "Nov Bill",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
            }),
            makeItem({
                key: "older:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-10-01T00:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: {
                    id: 104,
                    external_id: "HB 1",
                    title: "Oct Bill",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
            }),
        ];

        render(<Feed feed_match_count={0} items={items} />);

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
                bill: {
                    id: 201,
                    external_id: "HB 412",
                    title: "Fare cap",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
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
                bill: {
                    id: 202,
                    external_id: "S. 1820",
                    title: "Rural broadband",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
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

        render(<Feed feed_match_count={0} items={items} />);

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
                sway_locale: { id: 1, name: "Baltimore" },
                bill: {
                    id: 301,
                    external_id: "CB 1",
                    title: "Unvoted Bill",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
                user_support: null,
            }),
            makeItem({
                key: "voted:1",
                kind: "bill_of_the_month_released",
                occurred_at: "2026-11-01T00:00:00Z",
                sway_locale: { id: 2, name: "Maryland" },
                bill: {
                    id: 302,
                    external_id: "HB 2",
                    title: "Voted Bill",
                    summary: null,
                    view_count: 0,
                    share_count: 0,
                    summary_ai_unreviewed: false,
                },
                user_support: "AGAINST",
            }),
        ];

        render(<Feed feed_match_count={0} items={items} />);

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

    it("renders a labelled search input and debounces typing into feed_search with newest_keys, reset, and dropped feed_cursor", () => {
        window.history.replaceState({}, "", "/feed?feed_cursor=abc123");
        render(<Feed feed_match_count={0} items={[]} />);

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
            only: ["items", "feed_search", "feed_match_count", "newest_keys"],
            reset: ["items"],
        });
    });

    it("renders the clear button when searching and clears feed_search when clicked", () => {
        window.history.replaceState({}, "", "/feed?feed_search=housing&feed_cursor=abc123");
        render(
            <Feed
                feed_match_count={0}
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
            only: ["items", "feed_search", "feed_match_count", "newest_keys"],
            reset: ["items"],
        });
    });

    it("refreshes newest_keys alongside search results so stale unfiltered newest_keys never show a bogus Show N new banner", () => {
        const itemA = makeItem({ key: "item:a" });
        const matchingItem = makeItem({
            key: "botm:housing",
            kind: "bill_of_the_month_released",
            occurred_at: "2026-11-01T00:00:00Z",
            sway_locale: { id: 1, name: "Baltimore" },
            bill: {
                id: 101,
                external_id: "CB 101",
                title: "Housing stability",
                summary: null,
                view_count: 0,
                share_count: 0,
                summary_ai_unreviewed: false,
            },
        });

        const { rerender } = render(
            <Feed
                feed_match_count={0}
                items={[itemA, matchingItem]}
                newest_keys={["unseen:1", "item:a", "botm:housing"]}
            />,
        );
        expect(screen.getByRole("button", { name: "Show 1 new" })).toBeTruthy();

        const input = screen.getByLabelText("Search your feed") as HTMLInputElement;
        fireEvent.change(input, { target: { value: "housing" } });
        vi.advanceTimersByTime(400);

        expect(routerGet).toHaveBeenCalledTimes(1);
        expect(routerGet.mock.calls[0]?.[2]).toMatchObject({
            only: ["items", "feed_search", "feed_match_count", "newest_keys"],
            reset: ["items"],
        });

        rerender(
            <Feed feed_match_count={0} items={[matchingItem]} feed_search="housing" newest_keys={["botm:housing"]} />,
        );
        expect(screen.queryByRole("button", { name: /Show .* new/ })).toBeNull();
    });

    it("renders the match summary with the server's total match count, not the loaded item count, and no-match message with all bills link when empty", () => {
        const { rerender } = render(
            <Feed
                feed_match_count={45}
                items={[
                    makeItem({
                        key: "botm:1",
                        kind: "bill_of_the_month_released",
                        occurred_at: "2026-11-01T00:00:00Z",
                        sway_locale: { id: 1, name: "Baltimore" },
                        bill: {
                            id: 101,
                            external_id: "CB 1",
                            title: "Fare cap",
                            summary: null,
                            view_count: 0,
                            share_count: 0,
                            summary_ai_unreviewed: false,
                        },
                    }),
                    makeItem({
                        key: "botm:2",
                        kind: "bill_of_the_month_released",
                        occurred_at: "2026-11-01T00:00:00Z",
                        sway_locale: { id: 2, name: "Maryland" },
                        bill: {
                            id: 102,
                            external_id: "HB 2",
                            title: "Fare equity",
                            summary: null,
                            view_count: 0,
                            share_count: 0,
                            summary_ai_unreviewed: false,
                        },
                    }),
                ]}
                feed_search="fare"
            />,
        );

        expect(screen.getByText('45 items in your feed match "fare"')).toBeTruthy();
        expect(screen.queryByText('2 items in your feed match "fare"')).toBeNull();

        rerender(<Feed feed_match_count={0} items={[]} feed_search="fare" />);

        expect(screen.getByText(/Nothing in your feed matches "fare"/)).toBeTruthy();
        const allBillsLink = screen.getByRole("link", { name: "all bills" });
        expect(allBillsLink.getAttribute("href")).toBe("/bills");
    });

    it("subscribes to FeedChannel, polls newest_keys, and reloads newest_keys on feed_updated", () => {
        routerReload.mockClear();
        usePollMock.mockClear();
        subscriptionsCreate.mockClear();
        subscriptionUnsubscribe.mockClear();

        const { unmount } = render(<Feed feed_match_count={0} items={[makeItem({ key: "item:1" })]} />);

        expect(subscriptionsCreate).toHaveBeenCalledWith("FeedChannel", expect.any(Object));
        expect(usePollMock).toHaveBeenCalledWith(60000, { only: ["newest_keys"] }, { background: "pause" });

        channelCallbacks.current?.received?.({ type: "feed_updated" });
        expect(routerReload).toHaveBeenCalledWith({ only: ["newest_keys"] });
        expect(routerReload.mock.calls[0]?.[0]).not.toHaveProperty("preserveScroll");

        unmount();
        expect(subscriptionUnsubscribe).toHaveBeenCalledTimes(1);
    });

    it("renders Show 1 new, Show N new, and Show 20+ new in a polite live region, scrolling up only on router.get success and notifying on error", () => {
        routerGet.mockClear();
        const scrollToSpy = vi.spyOn(window, "scrollTo").mockImplementation(() => {});

        const shownItem = makeItem({ key: "shown:1" });
        const { rerender } = render(<Feed feed_match_count={0} items={[shownItem]} newest_keys={["shown:1"]} />);
        expect(screen.queryByRole("button", { name: /Show .* new/ })).toBeNull();

        rerender(<Feed feed_match_count={0} items={[shownItem]} newest_keys={["new:1", "shown:1"]} />);
        const oneButton = screen.getByRole("button", { name: "Show 1 new" });
        expect(oneButton.closest("[aria-live='polite']")).not.toBeNull();

        const twentyNewKeys = Array.from({ length: 20 }, (_, i) => `new:${i + 1}`);
        rerender(<Feed feed_match_count={0} items={[shownItem]} newest_keys={twentyNewKeys} />);
        expect(screen.getByRole("button", { name: "Show 20+ new" })).toBeTruthy();

        rerender(
            <Feed feed_match_count={0} items={[shownItem]} newest_keys={["new:1", "new:2", "new:3", "shown:1"]} />,
        );
        const threeButton = screen.getByRole("button", { name: "Show 3 new" });
        fireEvent.click(threeButton);

        expect(routerGet).toHaveBeenCalledWith(
            "/feed",
            {},
            expect.objectContaining({
                only: ["items", "feed_match_count", "newest_keys"],
                reset: ["items"],
                preserveState: true,
                onSuccess: expect.any(Function),
                onError: expect.any(Function),
            }),
        );
        const firstOptions = routerGet.mock.calls[0]?.[2] as {
            onSuccess?: () => void;
            onError?: (errors: Record<string, string>) => void;
        };
        expect(firstOptions).not.toHaveProperty("preserveScroll");
        expect(screen.getByRole("button", { name: "Show 3 new" })).toBeTruthy();
        expect(scrollToSpy).not.toHaveBeenCalled();

        act(() => {
            firstOptions.onError?.({});
        });
        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Could not search your feed.",
        });
        expect(screen.getByRole("button", { name: "Show 3 new" })).toBeTruthy();
        expect(scrollToSpy).not.toHaveBeenCalled();

        act(() => {
            firstOptions.onSuccess?.();
        });
        expect(scrollToSpy).toHaveBeenCalledWith({ top: 0, behavior: "smooth" });

        const reloadedItems = ["new:1", "new:2", "new:3", "shown:1"].map((key) => makeItem({ key }));
        rerender(
            <Feed feed_match_count={0} items={reloadedItems} newest_keys={["new:1", "new:2", "new:3", "shown:1"]} />,
        );
        expect(screen.queryByRole("button", { name: /Show .* new/ })).toBeNull();

        scrollToSpy.mockRestore();
    });

    it("clears carried feed_cursor when clicking Show N new from a scrolled page URL", () => {
        window.history.replaceState({}, "", "/feed?feed_cursor=some-cursor&feed_search=housing");
        const scrollToSpy = vi.spyOn(window, "scrollTo").mockImplementation(() => {});

        const shownItem = makeItem({ key: "shown:1" });
        render(
            <Feed feed_match_count={0} items={[shownItem]} feed_search="housing" newest_keys={["new:1", "shown:1"]} />,
        );

        fireEvent.click(screen.getByRole("button", { name: "Show 1 new" }));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [calledUrl, calledData, calledOptions] = routerGet.mock.calls[0];
        expect(calledOptions).toMatchObject({
            only: ["items", "feed_match_count", "newest_keys"],
            reset: ["items"],
            preserveState: true,
        });
        expect(calledOptions).not.toHaveProperty("preserveScroll");

        const visit = {
            url: new URL(calledUrl as string, "http://localhost"),
            method: "get",
            data: calledData,
            only: (calledOptions as { only: string[] }).only,
        } as unknown as PendingVisit;
        applyNavigationCarryToVisit(visit, {
            currentUrl: "http://localhost/feed?feed_cursor=some-cursor&feed_search=housing",
        });

        expect((visit.url as URL).searchParams.has("feed_cursor")).toBe(false);
        expect((visit.url as URL).searchParams.get("feed_search")).toBe("housing");

        scrollToSpy.mockRestore();
    });

    it("renders view_count and share_count with tabular-nums, and no voted text, only on items that have a bill", () => {
        render(
            <Feed
                feed_match_count={0}
                items={[
                    makeItem({
                        key: "botm:counts",
                        kind: "bill_of_the_month_released",
                        occurred_at: "2026-11-12T15:00:00Z",
                        sway_locale: { id: 1, name: "Baltimore" },
                        bill: {
                            id: 501,
                            external_id: "CB 501",
                            title: "Transit Funding",
                            summary: null,
                            view_count: 108,
                            share_count: 9,
                            summary_ai_unreviewed: false,
                        },
                    }),
                    makeItem({
                        key: "user_joined:counts",
                        kind: "user_joined",
                        occurred_at: "2026-11-12T10:00:00Z",
                    }),
                ]}
            />,
        );

        const viewedText = screen.getByText("108 viewed");
        const sharedText = screen.getByText("9 shared");
        expect(viewedText).toBeTruthy();
        expect(sharedText).toBeTruthy();
        expect(viewedText.closest(".tabular-nums")).not.toBeNull();
        expect(sharedText.closest(".tabular-nums")).not.toBeNull();
        expect(screen.queryByText(/voted/)).toBeNull();
        expect(screen.getAllByText(/viewed$/)).toHaveLength(1);
        expect(screen.getAllByText(/shared$/)).toHaveLength(1);
    });
});

describe("cleanFeedSummary", () => {
    it("strips *italic*, _italic_, **bold**, and __bold__ emphasis", () => {
        expect(cleanFeedSummary("Requires _urgent_ and *immediate* **city** __action__.")).toBe(
            "Requires urgent and immediate city action.",
        );
        expect(cleanFeedSummary("_Multi word italic_ and *another phrase*")).toBe(
            "Multi word italic and another phrase",
        );
    });

    it("preserves intra-word underscores, snake_case identifiers, and URLs containing underscores", () => {
        expect(cleanFeedSummary("amends section 12_3_4")).toBe("amends section 12_3_4");
        expect(cleanFeedSummary("compares fy_2026 and fy_2027")).toBe("compares fy_2026 and fy_2027");
        expect(cleanFeedSummary("See https://en.wikipedia.org/wiki/Baltimore_City_Council for background.")).toBe(
            "See https://en.wikipedia.org/wiki/Baltimore_City_Council for background.",
        );
        expect(
            cleanFeedSummary("Read [Baltimore_City_Council](https://en.wikipedia.org/wiki/Baltimore_City_Council)"),
        ).toBe("Read Baltimore_City_Council");
    });

    it("returns null for null, blank strings, and Summary pending placeholder", () => {
        expect(cleanFeedSummary(null)).toBeNull();
        expect(cleanFeedSummary(undefined)).toBeNull();
        expect(cleanFeedSummary("   ")).toBeNull();
        expect(cleanFeedSummary("Summary pending")).toBeNull();
    });
});

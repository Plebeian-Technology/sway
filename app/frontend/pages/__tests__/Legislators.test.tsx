// @lat: [[partial-reload-poll-lists#Partial reload poll lists]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const usePollMock =
    vi.fn<(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);
const routerPostMock = vi.fn<(url: string, data?: unknown, config?: unknown) => void>();

// Named `function usePoll` so the rules-of-hooks linter treats the mock as a hook.
vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) {
        usePollMock(interval, options, pollOptions);
    },
    router: {
        reload: vi.fn<() => void>(),
        post: (...args: unknown[]) => routerPostMock(...(args as [never])),
        on: vi.fn<(type: string, callback: unknown) => () => void>(() => vi.fn<() => void>()),
    },
    Link: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: (only: string[]) => scoreSubscriptionMock(only),
}));
vi.mock("app/frontend/hooks/useActiveThemeId", () => ({
    useActiveThemeId: () => "sway",
}));
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ id: 1, name: "baltimore-maryland-united_states" }, vi.fn<(locale: unknown) => void>()],
    useSwayLocales: () => ({ options: [] }),
}));

// Stub the card so the page renders only one level deep.
vi.mock("app/frontend/components/legislators/LegislatorCard", () => ({
    default: () => <div data-testid="legislator-card" />,
}));

interface ITabsMockProps {
    value?: string;
    onValueChange: (val: string) => void;
    children: React.ReactNode;
}

vi.mock("app/frontend/components/ui/tabs", () => ({
    Tabs: ({ value, onValueChange, children }: ITabsMockProps) => (
        <div data-testid="tabs" data-active={value}>
            <button type="button" data-testid="tab-current" onClick={() => onValueChange("current")}>
                Current term
            </button>
            <button type="button" data-testid="tab-lifetime" onClick={() => onValueChange("lifetime")}>
                Lifetime
            </button>
            <button type="button" data-testid="tab-history" onClick={() => onValueChange("history")}>
                History
            </button>
            {children}
        </div>
    ),
    TabsList: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    TabsTrigger: () => null,
    TabsContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import Legislators from "app/frontend/pages/Legislators";

afterEach(() => {
    cleanup();
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    routerPostMock.mockClear();
});

describe("Legislators — poll + score-subscription refresh contract", () => {
    it("polls every 15s with only:[legislators] and subscribes on the same tuple", () => {
        render(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={false}
                filters={{}}
            />,
        );

        // The interval and the prop list are both fixed by the web-and-mobile
        // refresh agreement — do not change 15000 or ["legislators"].
        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(15000, { only: ["legislators"] }, { background: "pause" });
        expect(scoreSubscriptionMock).toHaveBeenCalledWith(["legislators"]);

        // One constant declared at module level feeds both, so a refresh set off by
        // the poll and one set off by a websocket push ask for exactly the same
        // props — the very same array object.
        const pollOnly = usePollMock.mock.calls[0][1].only;
        const subscribedTuple = scoreSubscriptionMock.mock.calls[0][0];
        expect(pollOnly).toBe(subscribedTuple);
    });
});

// @lat: [[registration-dead-ends#The dead ends in registration#An empty list says which kind of empty it is]]
describe("Legislators — an empty list says which kind of empty it is", () => {
    const renderPage = (waiting: boolean) =>
        render(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={waiting}
                filters={{}}
            />,
        );

    it("says the term has ended, and hides Search again, when every term has finished", () => {
        const { getByTestId, queryByText } = renderPage(true);

        expect(getByTestId("legislators-count-line").textContent).toContain("The term has ended");
        expect(queryByText("Search again")).toBeNull();
    });

    it("offers Search again when Sway simply has nobody for this place", () => {
        const { getByTestId, queryByText } = renderPage(false);

        expect(getByTestId("legislators-count-line").textContent).toContain("No representatives found");
        expect(queryByText("Search again")).not.toBeNull();
    });

    it("posts to /user_legislators with canonical sway_locale_id payload when searching again", () => {
        const { getByRole } = renderPage(false);

        fireEvent.click(getByRole("button", { name: "Search again" }));

        expect(routerPostMock).toHaveBeenCalledWith(
            "/user_legislators",
            { sway_locale_id: 1 },
            expect.objectContaining({
                preserveState: true,
                preserveScroll: true,
            }),
        );
    });
});

describe("Legislators — cards past the first screenful mount as the reader approaches", () => {
    const ABOVE_FOLD_COUNT = 8;

    class IntersectionObserverStub {
        constructor() {}
        observe() {}
        unobserve() {}
        disconnect() {}
        takeRecords(): IntersectionObserverEntry[] {
            return [];
        }
    }

    const makeLegislators = (count: number): sway.ILegislator[] =>
        Array.from({ length: count }, (_, index) => ({
            id: index + 1,
            external_id: `rep-${index}`,
            sway_locale_id: 1,
            full_name: `Rep ${index}`,
        })) as unknown as sway.ILegislator[];

    const renderWith = (count: number) =>
        render(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={makeLegislators(count)}
                waiting_for_new_term={false}
                filters={{}}
            />,
        );

    beforeEach(() => {
        vi.stubGlobal("IntersectionObserver", IntersectionObserverStub);
    });

    afterEach(() => {
        vi.unstubAllGlobals();
    });

    it("mounts the first eight cards and leaves a placeholder for each of the rest", () => {
        const { getAllByTestId, queryAllByTestId } = renderWith(14);

        expect(getAllByTestId("legislator-card")).toHaveLength(ABOVE_FOLD_COUNT);
        expect(queryAllByTestId("mount-when-near-placeholder")).toHaveLength(14 - ABOVE_FOLD_COUNT);
    });

    it("mounts every card and adds no placeholder when the roster fits the threshold", () => {
        const { getAllByTestId, queryAllByTestId } = renderWith(ABOVE_FOLD_COUNT);

        expect(getAllByTestId("legislator-card")).toHaveLength(ABOVE_FOLD_COUNT);
        expect(queryAllByTestId("mount-when-near-placeholder")).toHaveLength(0);
    });
});

// @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
describe("Legislators — tab parameter namespace (Move the Legislators page's parameters onto its own namespace)", () => {
    const renderLegislators = () =>
        render(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={false}
                filters={{}}
            />,
        );

    it("derives the active tab from canonical ?legislators_tab= in the URL", () => {
        window.history.replaceState({}, "", "/legislators?legislators_tab=lifetime");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("lifetime");

        cleanup();
        window.history.replaceState({}, "", "/legislators?legislators_tab=history");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("history");
    });

    it("falls back to legacy ?tab= when ?legislators_tab= is absent", () => {
        window.history.replaceState({}, "", "/legislators?tab=lifetime");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("lifetime");

        cleanup();
        window.history.replaceState({}, "", "/legislators?tab=history");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("history");
    });

    it("gives precedence to ?legislators_tab= when both ?legislators_tab= and legacy ?tab= are present", () => {
        window.history.replaceState({}, "", "/legislators?legislators_tab=lifetime&tab=history");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("lifetime");

        cleanup();
        window.history.replaceState({}, "", "/legislators?legislators_tab=history&tab=lifetime");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("history");

        cleanup();
        window.history.replaceState({}, "", "/legislators?legislators_tab=bogus&tab=history");
        renderLegislators();
        expect(screen.getByTestId("tabs").getAttribute("data-active")).toBe("current");
    });

    it("writes legislators_tab and clears legacy tab on tab change", () => {
        window.history.replaceState({}, "", "/legislators?tab=history");
        renderLegislators();

        fireEvent.click(screen.getByTestId("tab-lifetime"));

        const searchParams = new URLSearchParams(window.location.search);
        expect(searchParams.get("legislators_tab")).toBe("lifetime");
        expect(isQueryParamCleared(searchParams, "tab")).toBe(true);
        const stripped = stripClearedQueryParams(window.location.search);
        expect(stripped).toBe("?legislators_tab=lifetime");
    });

    it("navigating away to default tab marks the tab parameter cleared on the address", () => {
        window.history.replaceState({}, "", "/legislators?legislators_tab=history&tab=history");
        renderLegislators();

        fireEvent.click(screen.getByTestId("tab-current"));

        const searchParams = new URLSearchParams(window.location.search);
        expect(isQueryParamCleared(searchParams, "legislators_tab")).toBe(true);
        expect(isQueryParamCleared(searchParams, "tab")).toBe(true);
        expect(searchParams.get("legislators_tab")).toBe("");
        expect(searchParams.get("tab")).toBe("");
        const stripped = stripClearedQueryParams(window.location.search);
        expect(stripped).toBe("");
    });
});

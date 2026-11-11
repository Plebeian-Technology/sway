// @lat: [[legislators-history-per-locale-state#Legislators History state is tracked per locale]]

import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const routerReload = vi.fn<(options: { only?: string[]; onSuccess?: () => void; onError?: () => void }) => void>();

vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll() {},
    router: {
        reload: (...args: unknown[]) => routerReload(...(args as [never])),
        post: vi.fn<(...args: unknown[]) => void>(),
        on: vi.fn<(type: string, callback: unknown) => () => void>(() => vi.fn<() => void>()),
    },
    Link: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({ useScoreSubscription: () => false }));
vi.mock("app/frontend/hooks/useActiveThemeId", () => ({
    useActiveThemeId: () => "sway",
}));

let swayLocaleId = 1;
const refreshPropsSeen: (string[] | undefined)[] = [];
const getSwayLocale = vi.fn<(swayLocaleId: number, options?: { onError?: () => void }) => void>();

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: (refreshProps?: string[]) => {
        refreshPropsSeen.push(refreshProps);
        return [{ id: swayLocaleId, name: "baltimore-maryland-united_states" }, getSwayLocale, undefined];
    },
    useSwayLocales: () => ({ options: [] }),
}));

vi.mock("app/frontend/components/legislators/LegislatorCard", () => ({
    default: () => <div data-testid="legislator-card" />,
}));

// The real picker is a <select> built from `options`, which this test file leaves
// empty. A plain button reaches the page's own onChange without dragging in the
// details of that control's markup.
vi.mock("app/frontend/components/locales/SwayLocalePicker", () => ({
    default: ({ onChange }: { onChange: (id: number) => void }) => (
        <div>
            <button type="button" data-testid="pick-locale-1" onClick={() => onChange(1)}>
                Baltimore
            </button>
            <button type="button" data-testid="pick-locale-3" onClick={() => onChange(3)}>
                Congress
            </button>
        </div>
    ),
}));

// Radix tab buttons do not respond to fireEvent in the fake browser. The stand-in
// this codebase already uses (see Notifications.test.tsx) exposes the change handler
// as plain buttons and renders every panel, so the checks here are about the page's
// own logic rather than the tab library's.
vi.mock("app/frontend/components/ui/tabs", () => ({
    Tabs: ({ value, onValueChange, children }: any) => (
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
    TabsList: ({ children }: any) => <div>{children}</div>,
    TabsTrigger: () => null,
    TabsContent: ({ children }: any) => <div>{children}</div>,
}));

import Legislators from "app/frontend/pages/Legislators";

const BALTIMORE_HISTORY = {
    sessions: [{ session_label: "2021–2023 Baltimore City Council", entries: [] }],
} as unknown as sway.legislatorHistory.IHistory;

const LEG_1: sway.ILegislator = {
    id: 101,
    external_id: "leg-101",
    sway_locale_id: 1,
    active: true,
    ended_on: null,
    term_start_year: 2023,
    term_end_year: 2027,
} as unknown as sway.ILegislator;

const LEG_1_MODIFIED: sway.ILegislator = {
    ...LEG_1,
    active: false,
    ended_on: "2026-11-01",
};

const renderPage = (history?: sway.legislatorHistory.IHistory, legislators: sway.ILegislator[] = []) =>
    render(
        <Legislators
            user={{} as sway.IUser}
            sway_locale={{} as sway.ISwayLocale}
            legislators={legislators}
            waiting_for_new_term={false}
            filters={{}}
            history={history}
        />,
    );

const openHistory = () => fireEvent.click(screen.getByTestId("tab-history"));
const lastRefreshProps = () => refreshPropsSeen.at(-1);

beforeEach(() => {
    swayLocaleId = 1;
    refreshPropsSeen.length = 0;
    routerReload.mockClear();
    getSwayLocale.mockClear();
    window.history.replaceState({}, "", "/legislators");
});

afterEach(cleanup);

describe("Legislators History across a locale switch", () => {
    it("requests History on first open", () => {
        renderPage();

        openHistory();

        expect(routerReload).toHaveBeenCalledTimes(1);
        expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
    });

    it("does not request it again on re-opening the same jurisdiction", () => {
        renderPage();

        openHistory();
        fireEvent.click(screen.getByTestId("tab-lifetime"));
        openHistory();

        expect(routerReload).toHaveBeenCalledTimes(1);
    });

    // @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
    it("requests again after a locale switch made with History closed", () => {
        const { rerender } = renderPage();
        openHistory();
        expect(routerReload).toHaveBeenCalledTimes(1);

        fireEvent.click(screen.getByTestId("tab-current"));
        swayLocaleId = 3;
        rerender(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={false}
                filters={{}}
            />,
        );
        openHistory();

        expect(routerReload).toHaveBeenCalledTimes(2);
    });

    // @lat: [[legislators-history-per-locale-state#Legislators History state is tracked per locale]]
    it("will not render a payload belonging to the outgoing jurisdiction", () => {
        window.history.replaceState({}, "", "/legislators?tab=history");
        const { rerender } = renderPage(BALTIMORE_HISTORY);

        expect(screen.getByText("2021–2023 Baltimore City Council")).toBeInTheDocument();

        swayLocaleId = 3;
        rerender(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={false}
                filters={{}}
                history={BALTIMORE_HISTORY}
            />,
        );

        expect(screen.queryByText("2021–2023 Baltimore City Council")).not.toBeInTheDocument();
    });

    it("does not carry one jurisdiction's History failure onto the next", () => {
        const { rerender } = renderPage();
        openHistory();

        act(() => routerReload.mock.calls[0][0].onError?.());
        expect(screen.getByTestId("legislators-history-error")).toBeInTheDocument();

        swayLocaleId = 3;
        rerender(
            <Legislators
                user={{} as sway.IUser}
                sway_locale={{} as sway.ISwayLocale}
                legislators={[]}
                waiting_for_new_term={false}
                filters={{}}
            />,
        );

        expect(screen.queryByTestId("legislators-history-error")).not.toBeInTheDocument();
    });

    // @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
    it("keeps showing the jurisdiction still in effect when the switch is refused", () => {
        window.history.replaceState({}, "", "/legislators?tab=history");
        renderPage(BALTIMORE_HISTORY);
        expect(screen.getByText("2021–2023 Baltimore City Council")).toBeInTheDocument();

        fireEvent.click(screen.getByTestId("pick-locale-3"));
        act(() => getSwayLocale.mock.calls.at(-1)?.[1]?.onError?.());

        expect(screen.getByText("2021–2023 Baltimore City Council")).toBeInTheDocument();
    });

    // @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
    it("restores the closed-tab History claim when the switch is refused", () => {
        renderPage();
        openHistory();
        expect(routerReload).toHaveBeenCalledTimes(1);

        fireEvent.click(screen.getByTestId("tab-current"));
        fireEvent.click(screen.getByTestId("pick-locale-3"));
        act(() => getSwayLocale.mock.calls.at(-1)?.[1]?.onError?.());
        openHistory();

        expect(routerReload).toHaveBeenCalledTimes(1);
    });

    // History travels with the switch only while it is on screen: it is the costly
    // payload that sending props on demand exists to avoid building.
    describe("what the switch asks the server to refresh", () => {
        it("omits History while its tab is closed", () => {
            renderPage();

            expect(lastRefreshProps()).toEqual(["legislators", "sway_locale"]);
        });

        it("includes History while its tab is open", () => {
            renderPage();

            openHistory();

            expect(lastRefreshProps()).toEqual(["legislators", "sway_locale", "history"]);
        });
    });

    describe("mid-session poll roster turnover invalidates History", () => {
        it("triggers an immediate re-fetch when active roster changes while History tab is active", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
            expect(routerReload.mock.calls[1][0].only).toEqual(["history"]);
        });

        it("hides stale history and renders legislators-history-error when mid-session roster reload fails", () => {
            window.history.replaceState({}, "", "/legislators?tab=history");
            const { rerender } = renderPage(BALTIMORE_HISTORY, [LEG_1]);
            expect(screen.getByText("2021–2023 Baltimore City Council")).toBeInTheDocument();

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);
            act(() => routerReload.mock.calls[0][0].onError?.());

            expect(screen.queryByText("2021–2023 Baltimore City Council")).not.toBeInTheDocument();
            expect(screen.getByTestId("legislators-history-error")).toBeInTheDocument();
        });

        it("clears cached history so reopening History tab re-fetches after roster change while tab is inactive", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            fireEvent.click(screen.getByTestId("tab-current"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);

            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("clears historyFailedFor when active roster changes while History tab is inactive", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            act(() => routerReload.mock.calls[0][0].onError?.());
            expect(screen.getByTestId("legislators-history-error")).toBeInTheDocument();

            fireEvent.click(screen.getByTestId("tab-current"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );

            expect(screen.queryByTestId("legislators-history-error")).not.toBeInTheDocument();
        });

        it("preserves cached history without re-fetching when poll returns identical roster", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[{ ...LEG_1 }]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);

            fireEvent.click(screen.getByTestId("tab-current"));
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[{ ...LEG_1 }]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);
        });

        it("triggers re-fetch on empty roster transition from populated to empty", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("triggers re-fetch on empty roster transition from empty to populated", () => {
            const { rerender } = renderPage(undefined, []);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("preserves cached history when empty roster remains empty across polls", () => {
            const { rerender } = renderPage(undefined, []);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);
        });

        it("triggers re-fetch when term_start_year changes in isolation", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            const modified = { ...LEG_1, term_start_year: 2024 };
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[modified]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("triggers re-fetch when term_end_year changes in isolation", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            const modified = { ...LEG_1, term_end_year: 2029 };
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[modified]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("triggers re-fetch when ended_on date is set in isolation", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            const modified = { ...LEG_1, ended_on: "2026-11-04" };
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[modified]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("triggers re-fetch when inactive representative is restored to active", () => {
            const { rerender } = renderPage(undefined, [LEG_1_MODIFIED]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(2);
        });

        it("triggers re-fetch when a legislator is added or removed from roster", () => {
            const LEG_2 = { ...LEG_1, id: 102, external_id: "leg-102" };
            const { rerender } = renderPage(undefined, [LEG_1]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1, LEG_2]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );
            expect(routerReload).toHaveBeenCalledTimes(2);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_2]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );
            expect(routerReload).toHaveBeenCalledTimes(3);
        });

        it("does not trigger re-fetch or mark history requested when user has never viewed History tab", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);
            expect(routerReload).not.toHaveBeenCalled();

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );

            expect(routerReload).not.toHaveBeenCalled();

            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);
        });

        it("preserves cached history without re-fetching when roster order changes without member or term changes", () => {
            const LEG_2 = { ...LEG_1, id: 102, external_id: "leg-102" };
            const { rerender } = renderPage(undefined, [LEG_1, LEG_2]);
            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_2, LEG_1]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);
        });

        it("detects a poll roster change that occurred during an in-flight locale switch once that switch fails", () => {
            window.history.replaceState({}, "", "/legislators?tab=history");
            const { rerender } = renderPage(BALTIMORE_HISTORY, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );
            expect(routerReload).not.toHaveBeenCalled();

            act(() => getSwayLocale.mock.calls.at(-1)?.[1]?.onError?.());

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });

        it("still invalidates History on a subsequent roster poll after re-selecting the active locale or switching 1 -> 3 -> 1 while in flight", () => {
            window.history.replaceState({}, "", "/legislators?tab=history");
            const { rerender } = renderPage(BALTIMORE_HISTORY, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-1"));
            expect(getSwayLocale).not.toHaveBeenCalled();

            fireEvent.click(screen.getByTestId("pick-locale-3"));
            fireEvent.click(screen.getByTestId("pick-locale-1"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });

        it("calls routerReload only once when opening History for the first time after a poll during a failed locale switch", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1_MODIFIED]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );
            expect(routerReload).not.toHaveBeenCalled();

            act(() => getSwayLocale.mock.calls.at(-1)?.[1]?.onError?.());
            expect(routerReload).not.toHaveBeenCalled();

            openHistory();

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });

        it("does not fire routerReload for the outgoing locale when opening History during an in-flight locale switch, and fetches History once the target locale settles", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));
            openHistory();

            expect(routerReload).not.toHaveBeenCalled();

            swayLocaleId = 3;
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });

        it("renders delivered History without getting stuck in loading when opening History during an in-flight switch and switching back to the starting locale", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));
            openHistory();
            fireEvent.click(screen.getByTestId("pick-locale-1"));

            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[LEG_1]}
                    waiting_for_new_term={false}
                    filters={{}}
                    history={BALTIMORE_HISTORY}
                />,
            );

            expect(screen.getByText("2021–2023 Baltimore City Council")).toBeInTheDocument();
        });

        it("clears deferred History claim when History is opened and closed back to Current Term during an in-flight switch so opening History after the target locale settles fetches History", () => {
            const { rerender } = renderPage(undefined, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));
            openHistory();
            fireEvent.click(screen.getByTestId("tab-current"));

            swayLocaleId = 3;
            rerender(
                <Legislators
                    user={{} as sway.IUser}
                    sway_locale={{} as sway.ISwayLocale}
                    legislators={[]}
                    waiting_for_new_term={false}
                    filters={{}}
                />,
            );
            expect(routerReload).not.toHaveBeenCalled();

            openHistory();
            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });

        it("fetches History for the active locale when an in-flight switch fails after the user opened History during the switch", () => {
            renderPage(undefined, [LEG_1]);

            fireEvent.click(screen.getByTestId("pick-locale-3"));
            openHistory();
            expect(routerReload).not.toHaveBeenCalled();

            act(() => getSwayLocale.mock.calls.at(-1)?.[1]?.onError?.());

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload.mock.calls[0][0].only).toEqual(["history"]);
        });
    });
});

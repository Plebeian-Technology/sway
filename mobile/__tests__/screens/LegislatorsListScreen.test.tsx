// @lat: [[mobile-jest-first-pass-test-notes#LegislatorsListScreen.test.tsx]]

// ── Fake modules. These have to be declared before the imports ───────────────

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

const mockUseLegislators = jest.fn();
jest.mock("../../src/hooks/useLegislators", () => ({
    useLegislators: (...args: unknown[]) => mockUseLegislators(...args),
}));

// useFocusedSync — a do-nothing stand-in. It calls refresh once when mounted, so
// the tests get one refresh without a repeating timer running.
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: ({ refresh }: { refresh: () => void }) => {
        refresh();
    },
}));

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(async () => ({})),
        post: jest.fn(async () => ({})),
        patch: jest.fn(async () => ({})),
        delete: jest.fn(async () => undefined),
    },
}));

// SkeletonCard reaches into react-native-reanimated's native code, so stand in for it.
jest.mock("../../src/components/SkeletonCard", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
        default: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
    };
});

// A stand-in that skips the Card/ThemeProvider/native-shadow chain. Exposes score + "Ended stamp" via
// testIDs so tests can see which numbers (current/lifetime/frozen) the screen picked for each card.
jest.mock("../../src/components/LegislatorCard", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    function StubLegislatorCard({
        legislator,
        testID,
        mode,
        historyEntry,
    }: {
        legislator: {
            id: number;
            full_name?: string;
            user_legislator_score?: { count_agreed?: number | string } | null;
            lifetime_score?: { count_agreed?: number | string } | null;
        };
        testID?: string;
        mode?: "current" | "lifetime";
        historyEntry?: { score: { count_agreed?: number | string }; termWindow: string };
    }) {
        const resolvedTestID = testID ?? `legislator-card-${legislator.id}`;
        const score = historyEntry
            ? historyEntry.score
            : mode === "lifetime"
              ? legislator.lifetime_score
              : legislator.user_legislator_score;
        return ReactMod.createElement(
            RNMod.View,
            { testID: resolvedTestID },
            ReactMod.createElement(RNMod.Text, null, legislator.full_name ?? "Legislator"),
            score
                ? ReactMod.createElement(
                      RNMod.Text,
                      { testID: `${resolvedTestID}-agreed` },
                      String(score.count_agreed ?? 0),
                  )
                : null,
            historyEntry ? ReactMod.createElement(RNMod.View, { testID: `${resolvedTestID}-ended-stamp` }) : null,
        );
    }
    return { LegislatorCard: StubLegislatorCard, default: StubLegislatorCard };
});

// OfflineBanner calls useSafeAreaInsets, so fake that too.
jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// SwayLocalePickerSheet and Pressable both call useTheme, so stand in for ThemeProvider.
jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// expo-haptics: Pressable calls impactAsync to buzz the phone.
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#What the mobile test environment has to stand in for]]
jest.mock("../../src/components/SwayLocalePickerSheet", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        SwayLocalePickerSheet: ({
            locales,
            onSelect,
            testID,
        }: {
            locales: { id: number }[];
            onSelect: (id: number) => void;
            testID?: string;
        }) =>
            ReactMod.createElement(
                RNMod.View,
                { testID: testID ?? "locale-picker-trigger" },
                (locales ?? []).map((locale) =>
                    ReactMod.createElement(RNMod.Pressable, {
                        key: locale.id,
                        testID: `select-locale-${locale.id}`,
                        onPress: () => onSelect(locale.id),
                    }),
                ),
            ),
    };
});

import React from "react";
import { fireEvent, render, screen, within } from "@testing-library/react-native";
import LegislatorsListScreen from "../../src/screens/LegislatorsListScreen";

function makeNav() {
    return { navigate: jest.fn() };
}

const LOCALES = [
    { id: 1, name: "baltimore-maryland-united_states" },
    { id: 2, name: "maryland-maryland-united_states" },
];

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: LOCALES,
};

const LEG_1 = {
    id: 1,
    full_name: "Alice Smith",
    title: "Senator",
    party: "Democrat",
    active: true,
    term_start_year: 2025,
    term_end_year: 2027,
    user_legislator_score: { count_agreed: 5, count_disagreed: 2, count_no_legislator_vote: 1 },
    lifetime_score: { count_agreed: 42, count_disagreed: 9, count_no_legislator_vote: 3 },
};

const LEG_2 = {
    id: 2,
    full_name: "Bob Jones",
    title: "Delegate",
    party: "Republican",
    active: true,
    term_start_year: 2025,
    term_end_year: 2027,
    user_legislator_score: null,
    lifetime_score: null,
};

const LEG_FORMER = {
    id: 3,
    full_name: "Carol Former",
    title: "Delegate",
    party: "Democrat",
    active: false,
    term_start_year: 2019,
    term_end_year: 2021,
    user_legislator_score: { count_agreed: 1, count_disagreed: 0, count_no_legislator_vote: 0 },
    lifetime_score: { count_agreed: 1, count_disagreed: 0, count_no_legislator_vote: 0 },
};

const HISTORY_ENTRY = {
    legislator: { id: 9, full_name: "Dana Retired", title: "Senator" },
    term: { term_start_year: 2021, term_end_year: 2023, title: "Senator" },
    score: { count_agreed: 3, count_disagreed: 1, count_no_legislator_vote: 0 },
    ended_reason: "term_ended" as const,
};

const HISTORY_WITH_SESSIONS = {
    sessions: [{ session_label: "2021–2023 General Assembly", entries: [HISTORY_ENTRY] }],
};

const HISTORY_EMPTY = { sessions: [] };

function mockOnline(
    legislators: unknown[],
    opts: {
        loading?: boolean;
        waitingForNewTerm?: boolean;
        history?: unknown;
        historyLoading?: boolean;
        historyError?: unknown;
        fetchHistory?: () => Promise<void>;
    } = {},
) {
    mockUseLegislators.mockReturnValue({
        data: legislators,
        waitingForNewTerm: opts.waitingForNewTerm ?? false,
        loading: opts.loading ?? false,
        error: null,
        refresh: jest.fn(),
        isOnline: true,
        history: opts.history ?? null,
        historyLoading: opts.historyLoading ?? false,
        historyError: opts.historyError ?? null,
        fetchHistory: opts.fetchHistory ?? jest.fn(async () => undefined),
    });
}

describe("LegislatorsListScreen (Phase 35 PARITY-08 rebuild)", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseLegislators.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
    });

    test("renders 'Legislators' title text", () => {
        mockOnline([LEG_1]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByText("Legislators")).toBeTruthy();
    });

    test("renders locale picker with testID=locale-picker-trigger", () => {
        mockOnline([LEG_1]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("locale-picker-trigger")).toBeTruthy();
    });

    test("renders EmptyState (testID=legislators-empty-state) when useLegislators returns empty array", () => {
        mockOnline([]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("legislators-empty-state")).toBeTruthy();
    });

    test("renders btn-search-again Pressable inside empty state", () => {
        mockOnline([]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("btn-search-again")).toBeTruthy();
    });

    // @lat: [[registration-dead-ends#The dead ends in registration#An empty list says which kind of empty it is]]
    test("says the term has ended and hides btn-search-again when waiting for the new term", () => {
        mockOnline([], { waitingForNewTerm: true });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        expect(screen.getByTestId("legislators-empty-state")).toBeTruthy();
        expect(screen.queryByTestId("btn-search-again")).toBeNull();
        expect(screen.getByText(/The term has ended/)).toBeTruthy();
    });

    test("renders FlatList (testID=legislators-list) when legislators are present", () => {
        mockOnline([LEG_1, LEG_2]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("legislators-list")).toBeTruthy();
        expect(screen.queryByTestId("legislators-empty-state")).toBeNull();
    });

    test("renders legislator full names in the list", () => {
        mockOnline([LEG_1, LEG_2]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByText("Alice Smith")).toBeTruthy();
        expect(screen.getByText("Bob Jones")).toBeTruthy();
    });

    // Checked by testIDs rather than a snapshot: the theme objects refer back to themselves, and the
    // snapshot formatter runs out of stack.
    test("snapshot: non-empty list state — legislator cards rendered with correct testIDs", () => {
        mockOnline([LEG_1, LEG_2]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("legislator-card-1")).toBeTruthy();
        expect(screen.getByTestId("legislator-card-2")).toBeTruthy();
        expect(screen.getByTestId("legislators-list")).toBeTruthy();
        expect(screen.queryByTestId("legislators-empty-state")).toBeNull();
    });
});

describe("LegislatorsListScreen (Phase 65 term toggle + History, D-05/D-08/D-09/D-10/D-11/D-28)", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseLegislators.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
    });

    // All three segments are always shown, even for someone who has served just
    // one term. Nothing is hidden depending on the data.
    test("renders the 3-segment control with Current term / Lifetime / History labels", () => {
        mockOnline([LEG_1, LEG_2]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("legislators-tabs")).toBeTruthy();
        expect(screen.getByText("Current term")).toBeTruthy();
        expect(screen.getByText("Lifetime")).toBeTruthy();
        expect(screen.getByText("History")).toBeTruthy();
    });

    test("Lifetime segment threads lifetime_score into LegislatorCard (whole-view flip)", () => {
        mockOnline([LEG_1]);
        render(<LegislatorsListScreen navigation={makeNav()} />);

        // Default (segment 0): current-term score (5 agreed).
        expect(screen.getByTestId("legislator-card-1-agreed").props.children).toBe("5");

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-1"));

        // Lifetime (segment 1): summed lifetime score (42 agreed).
        expect(screen.getByTestId("legislator-card-1-agreed").props.children).toBe("42");
    });

    test("History segment calls fetchHistory on first open, not again on re-selection", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));
        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));

        expect(fetchHistory).toHaveBeenCalledTimes(1);
    });

    // @lat: [[legislators-history-per-locale-state#Mobile: LegislatorsListScreen's historyRequestedFor]]
    test("History asks again after a locale switch instead of reusing the previous request", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));
        fireEvent.press(screen.getByTestId("select-locale-2"));
        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    // Switching locale while History is already open does not change tabs, so
    // nothing else would think to ask for the incoming locale's data.
    test("History reloads for the incoming locale when the switch happens while it is open", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        fireEvent.press(screen.getByTestId("select-locale-2"));

        // The locale is passed in by name. This runs before React re-renders with
        // the new locale, so a call with no argument would fetch the old one.
        expect(fetchHistory).toHaveBeenLastCalledWith(2);
    });

    test("switching locale away from History does not fetch it unasked", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("select-locale-2"));

        expect(fetchHistory).not.toHaveBeenCalled();
    });

    // Sessions list newest first; each entry carries an "Ended" stamp. [platform]: on mobile that's a
    // solid block of colour (StampedBadge), not an outline with a faded fill.
    test("History segment renders grouped session entries with the Ended stamp", () => {
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));

        expect(screen.getByText("2021–2023 General Assembly")).toBeTruthy();
        expect(screen.getByTestId("legislator-history-card-9-ended-stamp")).toBeTruthy();
        expect(screen.getByTestId("legislator-history-card-9-agreed").props.children).toBe("3");
    });

    // The History empty state reuses the shared EmptyState component, with the
    // same wording the web app uses.
    test("History segment renders the shared EmptyState when sessions is empty", () => {
        mockOnline([LEG_1], { history: HISTORY_EMPTY });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));

        expect(screen.getByTestId("legislators-history-empty")).toBeTruthy();
        expect(screen.getByText("No history yet")).toBeTruthy();
        expect(screen.getByText("History builds when terms end or your representatives change.")).toBeTruthy();
    });

    // A failed fetch shows an error with a retry button. It used to fall through
    // to an empty list instead, which looked exactly like "no history" and left
    // the user no way to try again.
    test("History segment renders an error state with a retry affordance when fetchHistory fails", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { historyError: new Error("network error"), fetchHistory });
        render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));

        expect(screen.getByTestId("legislators-history-error")).toBeTruthy();
        expect(screen.getByText("Couldn't load your history. Try again.")).toBeTruthy();

        fireEvent.press(screen.getByTestId("legislators-history-error-cta"));
        expect(fetchHistory).toHaveBeenCalledTimes(2); // once on tab open, once on retry
    });

    // For someone no longer in office, the first tab reads the term's year range
    // instead of "Current term". Same tab, different words.
    test("Former-rep first legislator relabels tab 1 to the term's year range", () => {
        mockOnline([LEG_FORMER]);
        render(<LegislatorsListScreen navigation={makeNav()} />);

        expect(screen.getByText("2019–2021")).toBeTruthy();
        expect(screen.queryByText("Current term")).toBeNull();
    });

    test("pressing History tab again invokes fetchHistory after active roster changes while on Current Term", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));

        const LEG_1_INACTIVE = { ...LEG_1, active: false };
        mockOnline([LEG_1_INACTIVE], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("rerendering with modified roster automatically invokes fetchHistory when History tab is open", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        const LEG_1_INACTIVE = { ...LEG_1, active: false };
        mockOnline([LEG_1_INACTIVE], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("rerendering with identical roster preserves cached history without duplicate fetches", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([{ ...LEG_1 }], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));
        mockOnline([{ ...LEG_1 }], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);
    });

    test("triggers fetchHistory on empty roster transition from populated to empty", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("invalidates history cache when roster empties and restores while on Current Term", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("preserves history state without duplicate fetches when empty roster repeatedly polls empty", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("triggers fetchHistory when term_start_year changes in isolation", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        const modified = { ...LEG_1, term_start_year: 2026 };
        mockOnline([modified], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("triggers fetchHistory when term_end_year changes in isolation", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        const modified = { ...LEG_1, term_end_year: 2028 };
        mockOnline([modified], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("triggers fetchHistory when ended_on date is set in isolation", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        const modified = { ...LEG_1, ended_on: "2026-11-04" };
        mockOnline([modified], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("triggers fetchHistory when inactive representative is restored to active", () => {
        const fetchHistory = jest.fn(async () => undefined);
        const inactive = { ...LEG_1, active: false };
        mockOnline([inactive], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("triggers fetchHistory when a legislator is added or removed from roster", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_1, LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(3);
    });

    test("does not trigger fetchHistory when roster changes but History tab was never requested", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).not.toHaveBeenCalled();

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).not.toHaveBeenCalled();

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);
    });

    test("defers invalidation while loading is true until fetch completes", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_2], { loading: true, history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_2], { loading: false, history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("does not fire duplicate fetchHistory when switching locale while History is open before new locale roster renders", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("select-locale-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("does not fire duplicate fetchHistory on rapid multi-locale switch before intermediate roster arrives", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("select-locale-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        fireEvent.press(screen.getByTestId("select-locale-1"));
        expect(fetchHistory).toHaveBeenCalledTimes(3);

        mockOnline([{ ...LEG_1 }], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(3);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(4);
    });

    test("invalidates History on subsequent poll after rapid 1 -> 2 -> 1 locale switch on Current Term tab before intermediate roster arrives", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("select-locale-2"));
        fireEvent.press(screen.getByTestId("select-locale-1"));
        expect(fetchHistory).not.toHaveBeenCalled();

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("invalidates cached history when returning to a locale whose roster changed while away on Current Term tab", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-0"));
        fireEvent.press(screen.getByTestId("select-locale-2"));
        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("select-locale-1"));
        const modifiedLeg1 = { ...LEG_1, active: false, ended_on: "2026-11-01" };
        mockOnline([modifiedLeg1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("does not invalidate or re-fetch History when roster order changes without member or term changes", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1, LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_2, LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(1);
    });

    test("triggers fetchHistory when switching from an empty-roster locale to another empty-roster locale and then polling a populated roster", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        mockOnline([], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        fireEvent.press(screen.getByTestId("select-locale-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(3);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(4);
    });

    test("re-selecting the already-active locale on the History tab does not call fetchHistory again and still invalidates on next roster poll", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        fireEvent.press(screen.getByTestId("select-locale-1"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        const modified = { ...LEG_1, active: false };
        mockOnline([modified], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);
    });

    test("calls fetchHistory only once when opening History while a previously visited un-cached locale is reloading an updated roster", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("select-locale-2"));
        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        mockOnline([LEG_2], { loading: true, history: HISTORY_WITH_SESSIONS, fetchHistory });
        fireEvent.press(screen.getByTestId("select-locale-1"));

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockOnline([LEG_2], { loading: false, history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(1);
    });

    test("fetches History for the new bootstrap locale when bootstrap.locale.id changes while History tab is open", () => {
        const fetchHistory = jest.fn(async () => undefined);
        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        const { rerender } = render(<LegislatorsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("legislators-tabs-segment-2"));
        expect(fetchHistory).toHaveBeenCalledTimes(1);

        mockUseBootstrap.mockReturnValue({
            bootstrap: {
                ...BASE_BOOTSTRAP,
                locale: { id: 2, name: "maryland-maryland-united_states" },
            },
            loading: false,
        });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);

        expect(fetchHistory).toHaveBeenCalledTimes(2);
        expect(fetchHistory).toHaveBeenLastCalledWith(2);

        mockOnline([LEG_2], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(2);

        mockOnline([LEG_1], { history: HISTORY_WITH_SESSIONS, fetchHistory });
        rerender(<LegislatorsListScreen navigation={makeNav()} />);
        expect(fetchHistory).toHaveBeenCalledTimes(3);
    });
});

describe("LegislatorsListScreen scroll layout", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseLegislators.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
    });

    test("keeps the locale picker and the term tabs inside the scrolling list", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
        mockOnline([LEG_1, LEG_2]);
        render(<LegislatorsListScreen navigation={makeNav()} />);
        const list = screen.getByTestId("legislators-list");
        expect(within(list).getByTestId("locale-picker-trigger")).toBeTruthy();
        expect(within(list).getByTestId("legislators-tabs")).toBeTruthy();
        expect(within(list).queryByTestId("legislators-brand-header")).toBeNull();
    });
});

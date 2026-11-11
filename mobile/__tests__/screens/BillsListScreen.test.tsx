// ── Fake modules. These have to be declared before the imports ───────────────

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

const mockUseBills = jest.fn();
const mockUseBillCategories = jest.fn();
jest.mock("../../src/hooks/useBills", () => ({
    useBills: (...args: unknown[]) => mockUseBills(...args),
    useBillCategories: (...args: unknown[]) => mockUseBillCategories(...args),
}));

// SkeletonCard reaches into react-native-reanimated's native code under
// jest-expo, so stand in for it.
jest.mock("../../src/components/SkeletonCard", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, {
                testID: testID ?? "skeleton-card",
            }),
        default: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, {
                testID: testID ?? "skeleton-card",
            }),
    };
});

// expo-haptics: the Pressable inside CategoryChipStrip makes the phone buzz.
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// BillCard is built from Card, which brings along useTheme, its bold shadow, and
// a Pressable. Standing in for it keeps snapshots shallow and avoids the stack
// overflow the snapshot formatter hits when it walks a whole list of Card and
// Pressable trees.
jest.mock("../../src/components/BillCard", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        BillCard: ({ bill, testID }: { bill: { id: number; title: string }; testID?: string }) =>
            ReactMod.createElement(
                RNMod.View,
                { testID: testID ?? `bill-card-${bill.id}` },
                ReactMod.createElement(RNMod.Text, null, bill.title),
            ),
        default: ({ bill, testID }: { bill: { id: number; title: string }; testID?: string }) =>
            ReactMod.createElement(
                RNMod.View,
                { testID: testID ?? `bill-card-${bill.id}` },
                ReactMod.createElement(RNMod.Text, null, bill.title),
            ),
    };
});

// OfflineBanner calls useSafeAreaInsets. Fake it so no native module is needed.
jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// SwayLocalePickerSheet calls useTheme, so stand in for ThemeProvider.
jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

import React from "react";
import { ActionSheetIOS, FlatList } from "react-native";
import { render, screen, fireEvent, within } from "@testing-library/react-native";
import BillsListScreen from "../../src/screens/BillsListScreen";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

function makeNav() {
    return { navigate: jest.fn() };
}

const LOCALES = [
    { id: 1, name: "Baltimore" },
    { id: 2, name: "Maryland" },
];

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: LOCALES,
};

const BILL_1 = {
    id: 1,
    title: "Bill One",
    category: "education",
    categories: ["Education"],
    external_id: "HB0001",
};
const BILL_2 = {
    id: 2,
    title: "Bill Two",
    category: "police",
    categories: ["Police"],
    external_id: "HB0002",
};
// Deliberately in two categories with a singular `category` field that matches neither — catches both
// an OR/AND filter mixup and a filter that wrongly checks `category` instead of `categories`.
const BILL_3 = {
    id: 3,
    title: "Bill Three",
    category: "infrastructure",
    categories: ["Education", "Police"],
    external_id: "HB0003",
};
// A bill with no categories at all — it has no `categories` key. Any filter that
// is switched on must hide it; it only shows when nothing is picked.
const BILL_4 = {
    id: 4,
    title: "Bill Four",
    category: "infrastructure",
    external_id: "HB0004",
};

function mockOnline(data: unknown[] | null, loading = false, extra: Record<string, unknown> = {}) {
    mockUseBills.mockReturnValue({
        data,
        loading,
        refresh: jest.fn(),
        isOnline: true,
        isResolved: true,
        page: 1,
        billsTotal: data?.length ?? 0,
        allCategories: ["Education", "Police", "Health", "Housing"],
        loadingMore: false,
        pageError: null,
        hasMore: false,
        loadMore: jest.fn(),
        ...extra,
    });
}
function mockOffline(data: unknown[] | null, loading = false, extra: Record<string, unknown> = {}) {
    // @lat: [[mobile-expo-config#The Expo config file and the mobile type check#What the mobile test environment has to stand in for]]
    mockUseBills.mockReturnValue({
        data,
        loading,
        refresh: jest.fn(),
        isOnline: false,
        isResolved: true,
        page: 1,
        billsTotal: data?.length ?? 0,
        allCategories: ["Education", "Police", "Health", "Housing"],
        loadingMore: false,
        pageError: null,
        hasMore: false,
        loadMore: jest.fn(),
        ...extra,
    });
}

describe("BillsListScreen (Phase 34 parity rewrite)", () => {
    // Fixed at four so snapshots stay stable across runs; beforeEach and the chip-count test below
    // both read this same list.
    const SERVER_CATEGORIES = ["Education", "Police", "Health", "Housing"] as const;

    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseBills.mockReset();
        mockUseBillCategories.mockReset();
        mockUseBootstrap.mockReturnValue({
            bootstrap: BASE_BOOTSTRAP,
            loading: false,
        });
        mockUseBillCategories.mockReturnValue({
            allCategories: SERVER_CATEGORIES,
        });
    });

    test("renders SkeletonCard placeholders while loading with no data (testID=bills-list-loading)", () => {
        mockUseBills.mockReturnValue({
            data: null,
            loading: true,
            refresh: jest.fn(),
            isOnline: true,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list-loading")).toBeTruthy();
        expect(screen.getAllByTestId("skeleton-card").length).toBeGreaterThanOrEqual(1);
    });

    test("renders 2 BillCard items inside FlatList (testID=bills-list) when data has 2 bills", () => {
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list")).toBeTruthy();
        expect(screen.getByText(BILL_1.title)).toBeTruthy();
        expect(screen.getByText(BILL_2.title)).toBeTruthy();
    });

    test("renders 'All Bills' title in BrandHeader and mode SegmentedControl by default", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getAllByText(PARITY_COPY.bills.allBillsTitle).length).toBeGreaterThanOrEqual(2);
        expect(screen.getByTestId("bills-mode-tabs")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.bills.pastBillsOfTheMonthTitle)).toBeTruthy();
    });

    test("tapping 'Past Bills of the Month' segment switches mode and passes listMode to useBills", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("bills-mode-tabs-segment-0"));
        expect(mockUseBills).toHaveBeenLastCalledWith(1, {
            listMode: "past_bills_of_the_month",
            legislativeSessionId: null,
        });
    });

    test("deep link route PastBillsOfTheMonth initializes screen in past_bills_of_the_month mode and navigating back to BillsList resets to all_bills", () => {
        mockOnline([BILL_1]);
        const { rerender } = render(<BillsListScreen navigation={makeNav()} route={{ name: "PastBillsOfTheMonth" }} />);
        expect(mockUseBills).toHaveBeenCalledWith(1, {
            listMode: "past_bills_of_the_month",
            legislativeSessionId: null,
        });

        mockUseBills.mockClear();
        rerender(<BillsListScreen navigation={makeNav()} route={{ name: "BillsList" }} />);
        expect(mockUseBills).toHaveBeenCalledWith(1, {
            listMode: "all_bills",
            legislativeSessionId: null,
        });
    });

    test("renders BillsSessionPickerSheet in all_bills mode, switches to a historical session, and resets legislativeSessionId to null when re-selecting the active session", () => {
        const sessions = [
            { id: 10, name: "2026 Session", active: true },
            { id: 9, name: "2024 Session", active: false },
        ];
        mockOnline([BILL_1], false, {
            legislativeSessions: sessions,
            selectedLegislativeSessionId: 10,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-session-picker-trigger")).toBeTruthy();
        expect(screen.getByText("Session: 2026 Session (Current)")).toBeTruthy();

        const spy = jest.spyOn(ActionSheetIOS, "showActionSheetWithOptions").mockImplementationOnce((_opts, cb) => {
            cb(2);
        });
        fireEvent.press(screen.getByTestId("bills-session-picker-trigger"));
        expect(mockUseBills).toHaveBeenLastCalledWith(1, {
            listMode: "all_bills",
            legislativeSessionId: 9,
        });

        spy.mockImplementationOnce((_opts, cb) => {
            cb(1);
        });
        fireEvent.press(screen.getByTestId("bills-session-picker-trigger"));
        expect(mockUseBills).toHaveBeenLastCalledWith(1, {
            listMode: "all_bills",
            legislativeSessionId: null,
        });
        spy.mockRestore();

        fireEvent.press(screen.getByTestId("bills-mode-tabs-segment-0"));
        expect(screen.queryByTestId("bills-session-picker-trigger")).toBeNull();
    });

    test("renders CATEGORIES label uppercase from PARITY_COPY.billsCategoriesLabel", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByText(PARITY_COPY.bills.categoriesLabel.toUpperCase())).toBeTruthy();
    });

    test("renders SwayLocalePickerSheet trigger row with testID=locale-picker-trigger", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("locale-picker-trigger")).toBeTruthy();
    });

    test("renders the CategoryChipStrip trigger (testID=category-chip-strip), which opens one row per server allCategories entry (4)", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("category-chip-strip")).toBeTruthy();
        // The rows live behind the trigger, so nothing category-shaped is on screen until it is pressed.
        expect(screen.queryAllByTestId(/^chip-/).length).toBe(0);
        fireEvent.press(screen.getByTestId("category-chip-strip"));
        expect(screen.getAllByTestId(/^chip-/).length).toBe(SERVER_CATEGORIES.length);
        SERVER_CATEGORIES.forEach((cat) => {
            expect(screen.getByTestId(`chip-${cat}`)).toBeTruthy();
        });
    });

    // A bill is kept if it has ANY of the chosen categories. BILL_3 is in two categories and BILL_4 in
    // none, so switching the filter to "has all" would hide BILL_3 and fail this test.
    test("toggling a category chip filters bill list via OR-intersection on bill.categories", () => {
        // BILL_1=["Education"], BILL_2=["Police"], BILL_3=["Education","Police"], BILL_4=no categories
        mockOnline([BILL_1, BILL_2, BILL_3, BILL_4]);
        render(<BillsListScreen navigation={makeNav()} />);
        // All four visible initially (no filter selected).
        expect(screen.queryByText(BILL_1.title)).toBeTruthy();
        expect(screen.queryByText(BILL_2.title)).toBeTruthy();
        expect(screen.queryByText(BILL_3.title)).toBeTruthy();
        expect(screen.queryByText(BILL_4.title)).toBeTruthy();

        // @lat: [[mobile-jest-first-pass-test-notes#BillsListScreen.test.tsx]]
        fireEvent.press(screen.getByTestId("category-chip-strip"));
        fireEvent.press(screen.getByTestId("chip-Education"));
        fireEvent.press(screen.getByTestId("category-filter-done"));
        expect(screen.queryByText(BILL_1.title)).toBeTruthy();
        expect(screen.queryByText(BILL_2.title)).toBeNull();
        expect(screen.queryByText(BILL_3.title)).toBeTruthy();
        expect(screen.queryByText(BILL_4.title)).toBeNull();
    });

    test("selecting two categories in one visit to the sheet shows the OR-union of both", () => {
        mockOnline([BILL_1, BILL_2, BILL_3, BILL_4]);
        render(<BillsListScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("category-chip-strip"));
        fireEvent.press(screen.getByTestId("chip-Education"));
        fireEvent.press(screen.getByTestId("chip-Police"));
        fireEvent.press(screen.getByTestId("category-filter-done"));
        // Education and Police between them cover BILL_1, BILL_2, and BILL_3. BILL_4 has neither.
        expect(screen.queryByText(BILL_1.title)).toBeTruthy();
        expect(screen.queryByText(BILL_2.title)).toBeTruthy();
        expect(screen.queryByText(BILL_3.title)).toBeTruthy();
        expect(screen.queryByText(BILL_4.title)).toBeNull();
    });

    test("the category trigger shows a count badge once categories are selected, and Clear all drops it", () => {
        mockOnline([BILL_1, BILL_2, BILL_3, BILL_4]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.queryByTestId("category-filter-count")).toBeNull();

        // Queries skip anything behind an open modal, so the trigger is read with the sheet closed.
        fireEvent.press(screen.getByTestId("category-chip-strip"));
        fireEvent.press(screen.getByTestId("chip-Education"));
        fireEvent.press(screen.getByTestId("chip-Police"));
        fireEvent.press(screen.getByTestId("category-filter-done"));
        expect(screen.getByTestId("category-filter-count")).toBeTruthy();
        expect(screen.getByText("2")).toBeTruthy();

        fireEvent.press(screen.getByTestId("category-chip-strip"));
        fireEvent.press(screen.getByTestId("category-filter-clear"));
        fireEvent.press(screen.getByTestId("category-filter-done"));
        expect(screen.queryByTestId("category-filter-count")).toBeNull();
        expect(screen.queryByText(BILL_4.title)).toBeTruthy();
    });

    test("renders EmptyState (testID=bills-empty-state) containing 'No bills found for' when data is empty", () => {
        mockOnline([]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-empty-state")).toBeTruthy();
        // The count line only renders when at least one bill is left, so the
        // "No bills found for" wording appears once, in the empty state, not twice.
        const matches = screen.getAllByText(/No bills found for/);
        expect(matches.length).toBe(1);
    });

    test("renders count string 'Showing N bills for locale.' matching PARITY_COPY.billsShowingCount", () => {
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);
        // The locale name comes from bootstrap.locale.name
        // ("baltimore-maryland-united_states"). Check just the "Showing 2 bills for" part.
        expect(screen.getByText(/Showing 2 bills for/)).toBeTruthy();
    });

    test("renders OfflineBanner (testID=offline-banner) when isOnline=false", () => {
        mockOffline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("offline-banner")).toBeTruthy();
    });

    test("does NOT render OfflineBanner when isOnline=true", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.queryByTestId("offline-banner")).toBeNull();
    });

    test("empty state renders EmptyState inside persistent FlatList with testID=bills-empty-state", () => {
        mockOnline([]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list")).toBeTruthy();
        expect(screen.getByTestId("bills-empty-state")).toBeTruthy();
    });

    // Checked by structure instead of a snapshot: turning the list into JSON runs out of stack under
    // jest-expo because React Native's list internals refer back to themselves.
    test("snapshot: 2-bill loaded state — bill cards rendered with correct testIDs", () => {
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bill-card-1")).toBeTruthy();
        expect(screen.getByTestId("bill-card-2")).toBeTruthy();
        expect(screen.getByTestId("bills-list")).toBeTruthy();
        expect(screen.queryByTestId("bills-empty-state")).toBeNull();
    });

    test("passes initial swayLocaleId from bootstrap.locale.id to useBills", () => {
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        expect(mockUseBills).toHaveBeenCalledWith(1, {
            listMode: "all_bills",
            legislativeSessionId: null,
        });
    });

    // The search box narrows the list on the device, ignoring capitalisation
    test("typing in the search input filters bills by case-insensitive title substring", () => {
        mockOnline([BILL_1, BILL_2, BILL_3]);
        render(<BillsListScreen navigation={makeNav()} />);
        fireEvent.changeText(screen.getByTestId("bills-search-input"), "TWO");
        expect(screen.queryByText(BILL_1.title)).toBeNull();
        expect(screen.queryByText(BILL_2.title)).toBeTruthy(); // "Bill Two"
        expect(screen.queryByText(BILL_3.title)).toBeNull();
        fireEvent.changeText(screen.getByTestId("bills-search-input"), "");
        expect(screen.queryByText(BILL_1.title)).toBeTruthy();
        expect(screen.queryByText(BILL_3.title)).toBeTruthy();
    });

    // The sort chips reorder the list on the device
    test("pressing a sort chip reorders the list (newest-first default -> Title A-Z)", () => {
        const ALPHA = {
            id: 10,
            title: "Alpha Act",
            external_id: "HB0010",
            introduced_date_time_utc: "2026-01-01",
        };
        const ZULU = {
            id: 11,
            title: "Zulu Act",
            external_id: "HB0011",
            introduced_date_time_utc: "2026-02-01",
        };
        mockOnline([ALPHA, ZULU]);
        render(<BillsListScreen navigation={makeNav()} />);

        const cardOrder = () => screen.getAllByTestId(/^bill-card-/).map((node) => node.props.testID);
        // Default order is newest first, so Zulu (February) comes before Alpha (January).
        expect(cardOrder()).toEqual(["bill-card-11", "bill-card-10"]);

        fireEvent.press(screen.getByTestId("sort-title:asc"));
        expect(cardOrder()).toEqual(["bill-card-10", "bill-card-11"]);
    });

    test("shows loading more activity indicator in footer when loadingMore is true", () => {
        mockOnline([BILL_1], false, { loadingMore: true, hasMore: true });
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list-loading-more")).toBeTruthy();
        expect(screen.getByLabelText("Loading more bills...")).toBeTruthy();
    });

    test("shows page retry banner in footer when pageError is present and calling it invokes loadMore", () => {
        const mockLoadMore = jest.fn();
        mockOnline([BILL_1], false, {
            pageError: new Error("Network timeout"),
            hasMore: true,
            loadMore: mockLoadMore,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list-page-error")).toBeTruthy();
        expect(screen.getByText("Could not load more bills.")).toBeTruthy();
        const retryBtn = screen.getByTestId("bills-retry-load-more");
        expect(retryBtn).toBeTruthy();
        fireEvent.press(retryBtn);
        expect(mockLoadMore).toHaveBeenCalledTimes(1);
    });

    test("shows search expansion prompt in footer when search finds 0 matches but hasMore is true, and pressing calls loadMore", () => {
        const mockLoadMore = jest.fn();
        mockOnline([BILL_1], false, {
            hasMore: true,
            loadMore: mockLoadMore,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        fireEvent.changeText(screen.getByTestId("bills-search-input"), "NonExistentBill");
        expect(screen.getByTestId("bills-empty-state")).toBeTruthy();
        expect(screen.getByTestId("bills-search-expand-prompt")).toBeTruthy();
        const expandBtn = screen.getByTestId("bills-load-next-page");
        expect(expandBtn).toBeTruthy();
        fireEvent.press(expandBtn);
        expect(mockLoadMore).toHaveBeenCalledTimes(1);
    });

    test("shows clean end divider when hasMore is false and bills are displayed", () => {
        mockOnline([BILL_1], false, { hasMore: false });
        render(<BillsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("bills-list-end-divider")).toBeTruthy();
    });

    test("triggers loadMore on FlatList onEndReached when hasMore is true and not loading", () => {
        const mockLoadMore = jest.fn();
        mockOnline([BILL_1], false, {
            hasMore: true,
            loadingMore: false,
            loading: false,
            loadMore: mockLoadMore,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        const flatList = screen.getByTestId("bills-list");
        fireEvent(flatList, "onEndReached");
        expect(mockLoadMore).toHaveBeenCalledTimes(1);
    });

    test("does not trigger loadMore on onEndReached when loadingMore is true", () => {
        const mockLoadMore = jest.fn();
        mockOnline([BILL_1], false, {
            hasMore: true,
            loadingMore: true,
            loading: false,
            loadMore: mockLoadMore,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        const flatList = screen.getByTestId("bills-list");
        fireEvent(flatList, "onEndReached");
        expect(mockLoadMore).not.toHaveBeenCalled();
    });

    test("does not trigger loadMore on onEndReached when hasMore is false", () => {
        const mockLoadMore = jest.fn();
        mockOnline([BILL_1], false, {
            hasMore: false,
            loadingMore: false,
            loading: false,
            loadMore: mockLoadMore,
        });
        render(<BillsListScreen navigation={makeNav()} />);
        const flatList = screen.getByTestId("bills-list");
        fireEvent(flatList, "onEndReached");
        expect(mockLoadMore).not.toHaveBeenCalled();
    });
});

describe("BillsListScreen scroll layout", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseBills.mockReset();
        mockUseBillCategories.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
        mockUseBillCategories.mockReturnValue({ allCategories: ["Education", "Police"] });
    });

    test("keeps every filter control inside the scrolling list", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);
        const list = screen.getByTestId("bills-list");
        [
            "bills-mode-tabs",
            "locale-picker-trigger",
            "bills-search-input",
            "bills-sort-strip",
            "category-chip-strip",
        ].forEach((id) => {
            expect(within(list).getByTestId(id)).toBeTruthy();
        });
    });

    test("pins only the brand header above the list", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
        mockOnline([BILL_1]);
        render(<BillsListScreen navigation={makeNav()} />);
        const list = screen.getByTestId("bills-list");
        expect(screen.getByTestId("bills-brand-header")).toBeTruthy();
        expect(within(list).queryByTestId("bills-brand-header")).toBeNull();
    });

    test("tapping the header title scrolls the bills list to offset 0", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
        const scrollToOffset = jest.spyOn(FlatList.prototype, "scrollToOffset").mockImplementation(() => undefined);
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByRole("button", { name: `${PARITY_COPY.bills.allBillsTitle}, scroll to top` }));

        expect(scrollToOffset).toHaveBeenCalledTimes(1);
        expect(scrollToOffset).toHaveBeenCalledWith({ offset: 0, animated: true });
        expect((scrollToOffset.mock.contexts[0] as FlatList).props.testID).toBe("bills-list");
        scrollToOffset.mockRestore();
    });

    test("the loading skeleton header has no scroll control, because no list is mounted", () => {
        mockUseBills.mockReturnValue({ data: null, loading: true, refresh: jest.fn(), isOnline: true });
        render(<BillsListScreen navigation={makeNav()} />);

        expect(screen.getByTestId("bills-brand-header")).toBeTruthy();
        expect(screen.queryByTestId("brand-header-title-button")).toBeNull();
    });

    test("typing in the search box keeps the same input mounted", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
        mockOnline([BILL_1, BILL_2]);
        render(<BillsListScreen navigation={makeNav()} />);
        const before = screen.getByTestId("bills-search-input");
        fireEvent.changeText(before, "One");
        const after = screen.getByTestId("bills-search-input");
        // A remounted input is a new node. React reuses the node only when the header is an element, not a
        // component function created during render.
        expect(after).toBe(before);
        expect(after.props.value).toBe("One");
        expect(screen.queryByText(BILL_2.title)).toBeNull();
    });
});

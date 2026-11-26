// @lat: [[mobile-bill-surface-components-design#BillScreenTabs#Why the featured screen fetches the bill detail too]]
const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true }),
}));
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => ({ submit: jest.fn(), isOnline: true, isResolved: true }),
}));
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: jest.fn(),
}));
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));
jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));
jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));
jest.mock("../../src/components/SkeletonCard", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
    };
});

const mockGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));

import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import BillOfTheMonthScreen from "../../src/screens/BillOfTheMonthScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const featuredBill = (id: number, title: string) => ({
    id,
    external_id: `HB${id}`,
    external_version: "1",
    title,
    summary: "A bill to improve transparency in government records.",
    summary_ai_unreviewed: false,
    link: "https://mgaleg.maryland.gov/bills/HB1234",
    chamber: "House",
    category: "government",
    status: "committee",
    active: true,
    scheduled_release_date_utc: null,
    audio_bucket_path: null,
    audio_by_line: null,
    vote_date_time_utc: null,
    introduced_date_time_utc: "2026-01-15T00:00:00Z",
    house_vote_date_time_utc: null,
    senate_vote_date_time_utc: null,
    vote: null,
    categories: ["Government"],
    legislator_id: 7,
    sway_locale_id: 1,
    created_at: "2026-01-15T00:00:00Z",
});

const firstBillDetail = {
    bill: { ...featuredBill(1, "Open Records Act"), related_articles: [], news_testimonies: [] },
    sponsor: { full_name: "Sen. Firstbill" },
    user_vote: null,
    bill_score: {
        id: 3,
        bill_id: 1,
        for_percent: 70,
        against_percent: 30,
        comparison_suppressed: false,
        districts: [],
    },
    districts: [],
    organizations: [],
    public_testimony_counts: null,
};

const bootstrapFeaturing = (bill: ReturnType<typeof featuredBill>) => ({
    bootstrap: {
        bill_of_the_month: bill,
        locale: { id: 1, name: "baltimore-maryland-united_states" },
        sway_locales: [{ id: 1, name: "Baltimore City, MD" }],
    },
    loading: false,
    error: null,
    refetch: jest.fn(),
    needsUpdate: false,
});

const screenElement = () => (
    <ThemeProvider initialMode="light">
        <BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />
    </ThemeProvider>
);

describe("BillOfTheMonthScreen when the featured bill changes", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockUseBootstrap.mockReset();
    });

    test("drops the previous bill's detail while the new bill's detail is still loading", async () => {
        mockGet.mockImplementation((url: string) =>
            url.startsWith("/bills/1?") ? Promise.resolve(firstBillDetail) : new Promise(() => {}),
        );
        mockUseBootstrap.mockReturnValue(bootstrapFeaturing(featuredBill(1, "Open Records Act")));
        const { rerender } = render(screenElement());

        await waitFor(() => expect(screen.getByText(/Sponsored by Sen\. Firstbill/)).toBeTruthy());
        fireEvent.press(screen.getByTestId("tab-votes"));
        await waitFor(() => expect(screen.getByText(/For: 70%/)).toBeTruthy());

        mockUseBootstrap.mockReturnValue(bootstrapFeaturing(featuredBill(2, "Clean Air Act")));
        rerender(screenElement());

        expect(mockGet).toHaveBeenCalledWith("/bills/2?with=legislator", expect.anything());
        expect(screen.getByText("Clean Air Act")).toBeTruthy();
        expect(screen.queryByText(/Firstbill/)).toBeNull();
        expect(screen.queryByText(/For: 70%/)).toBeNull();
        expect(screen.getByTestId("tab-bill").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
    });
});

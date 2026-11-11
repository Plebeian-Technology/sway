// @lat: [[mobile-jest-first-pass-test-notes#OrgsListScreen.test.tsx]]

// ── Hoisted mocks (must precede import) ──────────────────────────────────────

const mockUseOrganizations = jest.fn();
jest.mock("../../src/hooks/useOrganizations", () => ({
    useOrganizations: (filters: unknown) => mockUseOrganizations(filters),
}));

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

import React from "react";
import { render, screen } from "@testing-library/react-native";
import OrgsListScreen from "../../src/screens/OrgsListScreen";

function makeNav() {
    return { navigate: jest.fn(), getParent: jest.fn(() => ({ navigate: jest.fn() })) };
}

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: [{ id: 1, name: "baltimore-maryland-united_states" }],
};

const ORG_1 = { id: 1, name: "Alpha Org", sway_locale_slug: "baltimore-maryland-united_states" };
const ORG_2 = { id: 2, name: "Beta Org", sway_locale_slug: "baltimore-maryland-united_states" };

function mockOnlineOrgs(orgs: unknown[], loading = false) {
    mockUseOrganizations.mockReturnValue({
        data: { organizations: orgs, applied_filters: { locale_id: "1" } },
        loading,
        error: null,
        refresh: jest.fn(),
        isOnline: true,
    });
}

describe("OrgsListScreen (Phase 35 parity rebuild — RED)", () => {
    beforeEach(() => {
        mockUseOrganizations.mockReset();
        mockUseBootstrap.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
    });

    test("renders title 'Organizations'", () => {
        mockOnlineOrgs([ORG_1]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.getByText("Organizations")).toBeTruthy();
    });

    test("keeps the header title a plain heading with no scroll-to-top control", () => {
        mockOnlineOrgs([ORG_1]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("orgs-brand-header")).toBeTruthy();
        expect(screen.getByRole("header", { name: "Organizations" })).toBeTruthy();
        expect(screen.queryByTestId("brand-header-title-button")).toBeNull();
        expect(screen.queryByRole("button", { name: /scroll to top/i })).toBeNull();
    });

    test("renders testID='locale-picker-trigger' (SwayLocalePickerSheet header)", () => {
        mockOnlineOrgs([ORG_1]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("locale-picker-trigger")).toBeTruthy();
    });

    test("does NOT render testID='org-filter-bar' (OrgFilterBar removed per D-06)", () => {
        mockOnlineOrgs([ORG_1]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.queryByTestId("org-filter-bar")).toBeNull();
    });

    test("does NOT render any element with text 'Following' (follow model ripped per D-07)", () => {
        mockOnlineOrgs([ORG_1]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.queryByText(/Following/i)).toBeNull();
    });

    test("renders testID='orgs-list' FlatList when orgs are present", () => {
        mockOnlineOrgs([ORG_1, ORG_2]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("orgs-list")).toBeTruthy();
    });

    test("renders testID='orgs-empty-state' when orgs list is empty", () => {
        mockOnlineOrgs([]);
        render(<OrgsListScreen navigation={makeNav()} />);
        expect(screen.getByTestId("orgs-empty-state")).toBeTruthy();
    });

    test("snapshot: empty state", () => {
        mockOnlineOrgs([]);
        const { toJSON } = render(<OrgsListScreen navigation={makeNav()} />);
        expect(toJSON()).toMatchSnapshot();
    });
});

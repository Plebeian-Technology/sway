// @lat: [[mobile-jest-first-pass-test-notes#MembershipCard.test.tsx / MembershipsListScreen.test.tsx]]

jest.mock("../../src/hooks/useMemberships", () => ({
    useMemberships: jest.fn(),
}));
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ navigate: jest.fn() }),
}));
jest.mock("../../src/components/OfflineBanner", () => ({
    OfflineBanner: () => null,
}));
jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import React from "react";
import { render } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import MembershipsListScreen from "../../src/screens/MembershipsListScreen";
import { useMemberships } from "../../src/hooks/useMemberships";

const mockUseMemberships = useMemberships as jest.Mock;

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("MembershipsListScreen", () => {
    beforeEach(() => {
        mockUseMemberships.mockReset();
    });

    test("renders active and pending section testIDs", () => {
        mockUseMemberships.mockReturnValue({
            active: [{ id: 1, role: "standard", organization: { id: 2, name: "Org A", member_count: 3 } }],
            pending: [],
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getByTestId } = wrap(<MembershipsListScreen />);
        expect(getByTestId("memberships-active-section")).toBeTruthy();
        expect(getByTestId("memberships-pending-section")).toBeTruthy();
    });

    test("renders EmptyState when active list is empty", () => {
        mockUseMemberships.mockReturnValue({
            active: [],
            pending: [],
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getByTestId } = wrap(<MembershipsListScreen />);
        expect(getByTestId("memberships-active-section")).toBeTruthy();
    });

    test("renders MembershipCards for active memberships", () => {
        mockUseMemberships.mockReturnValue({
            active: [
                { id: 10, role: "standard", organization: { id: 2, name: "Alpha Org", member_count: 4 } },
                { id: 11, role: "admin", organization: { id: 3, name: "Beta Org", member_count: 7 } },
            ],
            pending: [],
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getByTestId } = wrap(<MembershipsListScreen />);
        expect(getByTestId("membership-card-10")).toBeTruthy();
        expect(getByTestId("membership-card-11")).toBeTruthy();
    });

    test("renders pending membership cards in pending section", () => {
        mockUseMemberships.mockReturnValue({
            active: [],
            pending: [{ id: 20, role: "standard", organization: { id: 5, name: "Pending Org", member_count: 2 } }],
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getByTestId } = wrap(<MembershipsListScreen />);
        expect(getByTestId("membership-card-20")).toBeTruthy();
    });

    test("has testID=memberships-list-screen", () => {
        mockUseMemberships.mockReturnValue({
            active: [],
            pending: [],
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        const { getByTestId } = wrap(<MembershipsListScreen />);
        expect(getByTestId("memberships-list-screen")).toBeTruthy();
    });
});

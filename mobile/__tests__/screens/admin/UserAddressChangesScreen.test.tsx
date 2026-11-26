import React from "react";
import { render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import UserAddressChangesScreen from "../../../src/screens/admin/UserAddressChangesScreen";

const change = {
    id: 1,
    user_id: 12,
    previous_address_id: 3,
    new_address_id: 4,
    deactivated_legislator_ids: [1, 2],
    activated_legislator_ids: [3],
    deactivated_district_ids: [10],
    activated_district_ids: [20],
    previous_sway_locale_ids: [5],
    new_sway_locale_ids: [6],
    previous_sway_locale_names: ["Baltimore, Maryland"],
    new_sway_locale_names: ["Annapolis, Maryland"],
    prior_vote_count: 2,
    prior_voted_bill_ids: [501, 502],
    prior_voted_sway_locale_ids: [5],
    cross_district: true,
    cross_sway_locale: false,
    voted_before_switch: true,
    user_switch_count: 2,
    created_at: "2026-11-01T12:00:00Z",
};

// @lat: [[mobile-admin-area#The user address changes screen]]
describe("UserAddressChangesScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("shows a change's locale names, prior vote count and flags", async () => {
        mockApiGet.mockResolvedValue({ user_address_changes: [change] });
        render(<UserAddressChangesScreen />);

        expect(await screen.findByText("User #12")).toBeTruthy();
        expect(screen.getByText("Baltimore, Maryland -> Annapolis, Maryland")).toBeTruthy();
        expect(screen.getByText("2 votes (Bills: 501, 502)")).toBeTruthy();
        expect(screen.getByText("Cross-district")).toBeTruthy();
        expect(screen.getByText("Voted before switch")).toBeTruthy();
        expect(screen.getByText("Repeat switcher")).toBeTruthy();
        expect(screen.queryByText("Cross-locale")).toBeNull();
        expect(screen.getByText("Address #3 -> #4")).toBeTruthy();
        expect(screen.getByText("10 -> 20")).toBeTruthy();
        expect(screen.getByText("1, 2 -> 3")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/user_address_changes", expect.anything());
    });

    it("shows an empty state when no switch has been recorded", async () => {
        mockApiGet.mockResolvedValue({ user_address_changes: [] });
        render(<UserAddressChangesScreen />);

        expect(await screen.findByText("No user address switches have been recorded.")).toBeTruthy();
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<UserAddressChangesScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});

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

import SharedAddressesScreen from "../../../src/screens/admin/SharedAddressesScreen";

// @lat: [[mobile-admin-area#The shared addresses screen]]
describe("SharedAddressesScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("lists each shared address with its user count", async () => {
        mockApiGet.mockResolvedValue({
            shared_addresses: [
                { address_ids: [7], user_count: 3 },
                { address_ids: [4, 9], user_count: 1 },
            ],
        });
        render(<SharedAddressesScreen />);

        expect(await screen.findByText("Address ID 7")).toBeTruthy();
        expect(screen.getByText("3 users")).toBeTruthy();
        expect(screen.getByText("Address ID 4, 9")).toBeTruthy();
        expect(screen.getByText("1 user")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/shared_addresses", expect.anything());
    });

    it("shows an empty state when no address is shared", async () => {
        mockApiGet.mockResolvedValue({ shared_addresses: [] });
        render(<SharedAddressesScreen />);

        expect(await screen.findByText("No address has been given by more than one registered user.")).toBeTruthy();
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<SharedAddressesScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});

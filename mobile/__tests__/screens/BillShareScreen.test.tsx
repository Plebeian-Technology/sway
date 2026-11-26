const mockReplace = jest.fn();
const mockNavigation = { replace: mockReplace };

jest.mock("../../src/api/client", () => ({ apiClient: { get: jest.fn() } }));

jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => mockNavigation,
}));

jest.mock("../../src/components/SkeletonCard", () => {
    const { View } = require("react-native");
    return { SkeletonCard: () => <View testID="skeleton-card" /> };
});

import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import BillShareScreen from "../../src/screens/BillShareScreen";
import { apiClient } from "../../src/api/client";
import { ApiRequestError, NetworkError } from "../../src/api/errors";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const mockGet = apiClient.get as jest.Mock;
const SHARE_UUID = "550e8400-e29b-41d4-a716-446655440000";

const open = (shareUuid: string) =>
    render(
        <ThemeProvider initialMode="light">
            <BillShareScreen route={{ params: { shareUuid } }} />
        </ThemeProvider>,
    );

// @lat: [[well-known-controller-notes#Mobile: linking.ts#A bill share link opens the shared bill]]
describe("BillShareScreen", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockReplace.mockReset();
    });

    it("shows the loading state while it asks the server for the share", () => {
        mockGet.mockReturnValue(new Promise(() => {}));

        open(SHARE_UUID);

        expect(screen.getByTestId("bill-share-loading")).toBeTruthy();
        expect(mockGet).toHaveBeenCalledWith(`/bill_shares/${SHARE_UUID}`);
    });

    it("replaces itself with the shared bill's detail screen", async () => {
        mockGet.mockResolvedValue({
            id: 9,
            bill_id: 42,
            share_uuid: SHARE_UUID,
            share_path: `/bill_shares/${SHARE_UUID}`,
        });

        open(SHARE_UUID);

        await waitFor(() => expect(mockReplace).toHaveBeenCalledWith("BillDetail", { id: 42 }));
    });

    it.each([
        ["a 404", new ApiRequestError("not_found", "Bill not found.", undefined, 404)],
        ["a network failure", new NetworkError("network_error", "Network request failed")],
    ])("shows a message and a way to the bills list on %s", async (_name, error) => {
        mockGet.mockRejectedValue(error);

        open(SHARE_UUID);

        await screen.findByText("Bill not found.");
        fireEvent.press(screen.getByTestId("bill-share-error-cta"));
        expect(mockReplace).toHaveBeenCalledWith("BillsList");
    });

    it.each(["..%2Fsomething", "not-a-uuid!", "123/456", ""])(
        "shows the message without calling the server for the share uuid %p",
        (shareUuid) => {
            open(shareUuid);

            expect(mockGet).not.toHaveBeenCalled();
            expect(screen.getByText("Bill not found.")).toBeTruthy();
        },
    );
});

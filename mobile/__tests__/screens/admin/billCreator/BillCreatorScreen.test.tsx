import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ setParams: jest.fn() }),
}));

jest.mock("../../../../src/components/admin/billCreator/BillFieldsSection", () => {
    const { Text } = jest.requireActual("react-native");
    return { __esModule: true, default: () => <Text>Bill fields</Text> };
});

import BillCreatorScreen from "../../../../src/screens/admin/billCreator/BillCreatorScreen";

const routeFor = (billId: number | null) => ({
    key: "AdminBillCreator-1",
    name: "AdminBillCreator" as const,
    params: { billId },
});

const page = { bill: { id: 42, external_id: "25-0042", title: "Rent Stabilization" } };

// @lat: [[mobile-bill-creator#The bill creator screen]]
describe("BillCreatorScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue(page);
    });

    it("opens a bill on the Creator tab", async () => {
        render(<BillCreatorScreen route={routeFor(42)} />);

        expect(await screen.findByText("Bill fields")).toBeTruthy();
        expect(screen.getByText("25-0042")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/creator", expect.anything());
    });

    it.each([
        [1, "Schedule", "schedule"],
        [2, "Pipeline", "pipeline"],
        [3, "Summary", "summary"],
        [4, "Positions", "positions"],
    ])("switches to the %s segment's tab and requests its path", async (index, label, path) => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");

        fireEvent.press(screen.getByTestId(`admin-bill-creator-tabs-segment-${index}`));

        expect(await screen.findByText(`The ${label} tab is not on mobile yet.`)).toBeTruthy();
        expect(mockApiGet).toHaveBeenLastCalledWith(`/admin/bill_creator/42/${path}`, expect.anything());
    });

    it("opens a new bill on the Creator tab", async () => {
        render(<BillCreatorScreen route={routeFor(null)} />);

        expect(await screen.findByText("Bill fields")).toBeTruthy();
        expect(screen.getByText("New bill")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/new?bill_creator_tab=creator", expect.anything());
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(new ApiRequestError("not_found", "Bill not found.", undefined, 404));
        render(<BillCreatorScreen route={routeFor(42)} />);

        expect(await screen.findByText("Bill not found.")).toBeTruthy();
        await waitFor(() => expect(screen.queryByText("Bill fields")).toBeNull());
    });
});

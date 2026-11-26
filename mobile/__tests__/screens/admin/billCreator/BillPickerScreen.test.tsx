import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

const mockNavigate = jest.fn();
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ navigate: mockNavigate }),
}));

import BillPickerScreen from "../../../../src/screens/admin/billCreator/BillPickerScreen";

const bill = (id: number, external_id: string, title: string) => ({ id, external_id, title });

const page = {
    bills: [bill(1, "25-0042", "Rent Stabilization"), bill(2, "25-0100", "Tree Canopy Protection")],
    legislators: [],
};

// @lat: [[mobile-bill-creator#The bill picker]]
describe("BillPickerScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("lists the bills from the new bill creator page", async () => {
        mockApiGet.mockResolvedValue(page);
        render(<BillPickerScreen />);

        expect(await screen.findByText("25-0042")).toBeTruthy();
        expect(screen.getByText("Tree Canopy Protection")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/new", expect.anything());
    });

    it("filters the bills by external id and by title as the admin types", async () => {
        mockApiGet.mockResolvedValue(page);
        render(<BillPickerScreen />);
        await screen.findByText("25-0042");

        fireEvent.changeText(screen.getByTestId("admin-bill-picker-search-input"), "canopy");
        expect(screen.queryByText("25-0042")).toBeNull();
        expect(screen.getByText("25-0100")).toBeTruthy();

        fireEvent.changeText(screen.getByTestId("admin-bill-picker-search-input"), "0042");
        expect(screen.getByText("25-0042")).toBeTruthy();
        expect(screen.queryByText("25-0100")).toBeNull();

        fireEvent.changeText(screen.getByTestId("admin-bill-picker-search-input"), "no such bill");
        expect(screen.getByText("No bills match your search.")).toBeTruthy();
        expect(screen.getByText("New bill")).toBeTruthy();
    });

    it("opens the bill creator for a tapped bill", async () => {
        mockApiGet.mockResolvedValue(page);
        render(<BillPickerScreen />);

        fireEvent.press(await screen.findByTestId("admin-bill-picker-bill-2"));

        expect(mockNavigate).toHaveBeenCalledWith("AdminBillCreator", { billId: 2 });
    });

    it("opens the bill creator with no bill for New bill", async () => {
        mockApiGet.mockResolvedValue(page);
        render(<BillPickerScreen />);

        fireEvent.press(await screen.findByTestId("admin-bill-picker-new"));

        expect(mockNavigate).toHaveBeenCalledWith("AdminBillCreator", { billId: null });
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(new ApiRequestError("forbidden", "You are not an admin.", undefined, 403));
        render(<BillPickerScreen />);

        expect(await screen.findByText("You are not an admin.")).toBeTruthy();
    });
});

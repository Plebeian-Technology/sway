import React from "react";
import { RefreshControl } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

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
    useFocusEffect: jest.fn(),
}));

jest.mock("../../../../src/screens/admin/billCreator/tabs/CreatorTab", () => {
    const { Pressable, Text } = jest.requireActual("react-native");
    return {
        __esModule: true,
        default: ({ refresh }: { refresh: () => Promise<void> }) => (
            <>
                <Text>Bill fields</Text>
                <Pressable testID="background-refresh" onPress={() => void refresh()} />
            </>
        ),
    };
});

jest.mock("../../../../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({ bootstrap: { locale: null } }),
}));

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
        [3, "Summary", "summary"],
        [4, "Positions", "positions"],
    ])("switches to the %s segment's tab and requests its path", async (index, label, path) => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");

        fireEvent.press(screen.getByTestId(`admin-bill-creator-tabs-segment-${index}`));

        expect(await screen.findByText(`The ${label} tab is not on mobile yet.`)).toBeTruthy();
        expect(mockApiGet).toHaveBeenLastCalledWith(`/admin/bill_creator/42/${path}`, expect.anything());
    });

    it("switches to the Schedule tab and requests its path", async () => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");

        fireEvent.press(screen.getByTestId("admin-bill-creator-tabs-segment-1"));

        expect(await screen.findByTestId("admin-schedule-selected")).toBeTruthy();
        expect(mockApiGet).toHaveBeenLastCalledWith("/admin/bill_creator/42/schedule", expect.anything());
    });

    it("switches to the Pipeline tab and requests its path", async () => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");

        fireEvent.press(screen.getByTestId("admin-bill-creator-tabs-segment-2"));

        expect(await screen.findByTestId("admin-pipeline-stages")).toBeTruthy();
        expect(mockApiGet).toHaveBeenLastCalledWith("/admin/bill_creator/42/pipeline", expect.anything());
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

    it("keeps the pull spinner off and the data shown during a background refresh", async () => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");
        mockApiGet.mockReturnValue(new Promise(() => {}));

        fireEvent.press(screen.getByTestId("background-refresh"));

        expect(screen.UNSAFE_getByType(RefreshControl).props.refreshing).toBe(false);
        expect(screen.getByText("Bill fields")).toBeTruthy();
    });

    it("shows the pull spinner while a pull refreshes", async () => {
        render(<BillCreatorScreen route={routeFor(42)} />);
        await screen.findByText("Bill fields");
        let finish: (value: typeof page) => void = () => {};
        mockApiGet.mockReturnValue(new Promise((resolve) => (finish = resolve)));

        act(() => {
            screen.UNSAFE_getByType(RefreshControl).props.onRefresh();
        });
        expect(screen.UNSAFE_getByType(RefreshControl).props.refreshing).toBe(true);

        await act(async () => finish(page));
        expect(screen.UNSAFE_getByType(RefreshControl).props.refreshing).toBe(false);
    });
});

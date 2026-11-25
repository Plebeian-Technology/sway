import React from "react";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

const mockDispatch = jest.fn();
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ dispatch: mockDispatch }),
    DrawerActions: { openDrawer: () => ({ type: "OPEN_DRAWER" }) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

const mockToolScreens: Record<string, string> = {};
jest.mock("../../../src/screens/admin/adminToolScreens", () => ({
    get adminToolScreens() {
        return mockToolScreens;
    },
}));

import AdminHubScreen from "../../../src/screens/admin/AdminHubScreen";

const HUB = {
    tools: [
        {
            id: "bill_creator",
            label: "Bill Creator",
            description: "Create and edit bills.",
            path: "/bill_creator/new",
            group: "Content",
            external: false,
        },
        {
            id: "categories",
            label: "Categories",
            description: "Manage categories.",
            path: "/admin/categories",
            group: "Content",
            external: false,
        },
        {
            id: "llm_settings",
            label: "LLM Settings",
            description: "Choose the model.",
            path: "/admin/llm_settings",
            group: "Settings",
            external: false,
        },
        {
            id: "beszel",
            label: "Beszel",
            description: "Monitor the host.",
            path: "https://beszel.example.com",
            group: "Operations",
            external: true,
        },
    ],
    database_health: {
        databases: [{ name: "primary", database_bytes: 2048, wal_bytes: 0 }],
        solid_queue_ready: 3,
        solid_queue_failed: 1,
    },
};

const renderScreen = () => {
    const navigation = { navigate: jest.fn() };
    render(<AdminHubScreen navigation={navigation} />);
    return navigation;
};

// @lat: [[mobile-admin-area#The hub screen]]
describe("AdminHubScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        for (const id of Object.keys(mockToolScreens)) delete mockToolScreens[id];
        mockApiGet.mockResolvedValue(HUB);
    });

    it("lists the tool labels under their group headings", async () => {
        renderScreen();

        expect(await screen.findByText("Bill Creator")).toBeTruthy();
        expect(screen.getByText("LLM Settings")).toBeTruthy();
        expect(screen.getByText("Content")).toBeTruthy();
        expect(screen.getByText("Settings")).toBeTruthy();
        expect(screen.getByText("Operations")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin", expect.anything());
    });

    it("shows a tool with no mobile screen, and an external tool, as disabled", async () => {
        renderScreen();

        const row = await screen.findByTestId("admin-tool-llm_settings");
        expect(within(row).getByText("Not on mobile yet")).toBeTruthy();
        expect(screen.queryByTestId("admin-tool-llm_settings-chevron")).toBeNull();
        expect(within(screen.getByTestId("admin-tool-beszel")).getByText("Not on mobile yet")).toBeTruthy();
    });

    it("keeps an external tool disabled even when the map names its id", async () => {
        mockToolScreens.beszel = "AdminBeszel";
        const navigation = renderScreen();

        fireEvent.press(await screen.findByTestId("admin-tool-beszel"));

        expect(navigation.navigate).not.toHaveBeenCalled();
    });

    it("navigates to the mapped route when the map has the tool id", async () => {
        mockToolScreens.categories = "AdminCategories";
        const navigation = renderScreen();

        const row = await screen.findByTestId("admin-tool-categories");
        expect(within(row).getByText("Manage categories.")).toBeTruthy();
        fireEvent.press(row);

        expect(navigation.navigate).toHaveBeenCalledWith("AdminCategories");
    });

    it("lists database sizes and job counts", async () => {
        renderScreen();

        expect(await screen.findByText("primary")).toBeTruthy();
        expect(screen.getByText("DB: 2.0 KB · WAL: 0 B")).toBeTruthy();
        expect(within(screen.getByTestId("admin-ready-jobs")).getByText("3")).toBeTruthy();
        expect(within(screen.getByTestId("admin-failed-jobs")).getByText("1")).toBeTruthy();
    });

    it("shows the server's message when GET /admin fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        renderScreen();

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
        expect(screen.queryByText("Bill Creator")).toBeNull();
    });

    it("opens the drawer from the menu button", async () => {
        renderScreen();

        fireEvent.press(await screen.findByLabelText("Open menu"));

        expect(mockDispatch).toHaveBeenCalledWith({ type: "OPEN_DRAWER" });
    });
});

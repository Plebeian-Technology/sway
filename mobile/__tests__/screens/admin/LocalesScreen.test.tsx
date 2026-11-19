import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
    },
}));

jest.mock("../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import LocalesScreen from "../../../src/screens/admin/LocalesScreen";

const baltimore = {
    id: 7,
    label: "Baltimore, Maryland",
    user_count: 1200,
    sample_street: "100 N Holliday St",
    sample_postal_code: "21202",
    sample_latitude: 39.29105,
    sample_longitude: -76.61069,
    summarization_instruction: null,
    news_sources: [],
};

const maryland = {
    ...baltimore,
    id: 8,
    label: "Maryland",
    user_count: 1500,
    sample_street: null,
    sample_postal_code: null,
    sample_latitude: null,
    sample_longitude: null,
};

const tiers = [
    { key: "city", label: "City", locales: [baltimore] },
    { key: "state", label: "State", locales: [maryland] },
    { key: "congress", label: "U.S. Congress", locales: [] },
];

// @lat: [[mobile-admin-area#The locales screen]]
describe("LocalesScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue({ tiers });
    });

    it("lists the locales under their tier with user counts", async () => {
        render(<LocalesScreen />);

        expect(await screen.findByText("Baltimore, Maryland")).toBeTruthy();
        expect(screen.getByText("City")).toBeTruthy();
        expect(screen.getByText("State")).toBeTruthy();
        expect(screen.getByText("U.S. Congress")).toBeTruthy();
        expect(screen.getByText("1,200 users")).toBeTruthy();
        expect(screen.getByText("No locales yet.")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/locales", expect.anything());
    });

    it("offers to add a sample address only where none is set", async () => {
        render(<LocalesScreen />);

        await screen.findByText("Maryland");
        expect(screen.getByTestId("admin-locale-7-toggle")).toHaveTextContent("Sample address");
        expect(screen.getByTestId("admin-locale-8-toggle")).toHaveTextContent("Add sample address");
    });

    it("saves an edited sample street with a PATCH and refreshes the list", async () => {
        mockApiPatch.mockResolvedValue({ sway_locale: { id: 7 } });
        render(<LocalesScreen />);

        await screen.findByText("Baltimore, Maryland");
        fireEvent.press(screen.getByTestId("admin-locale-7-toggle"));
        expect(screen.getByTestId("admin-locale-7-street-input").props.value).toBe("100 N Holliday St");
        expect(screen.getByTestId("admin-locale-7-latitude-input").props.value).toBe("39.29105");

        fireEvent.changeText(screen.getByTestId("admin-locale-7-street-input"), "200 E Pratt St");
        fireEvent.press(screen.getByTestId("admin-locale-7-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/locales/7", {
                sway_locale: {
                    sample_street: "200 E Pratt St",
                    sample_postal_code: "21202",
                    sample_latitude: "39.29105",
                    sample_longitude: "-76.61069",
                },
            }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        expect(screen.queryByTestId("admin-locale-7-street-input")).toBeNull();
    });

    it("shows the server's message and keeps the form open when the save is rejected", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("validation_failed", "Validation failed: Sample latitude is invalid", undefined, 422),
        );
        render(<LocalesScreen />);

        await screen.findByText("Baltimore, Maryland");
        fireEvent.press(screen.getByTestId("admin-locale-7-toggle"));
        fireEvent.press(screen.getByTestId("admin-locale-7-save"));

        expect(await screen.findByText("Validation failed: Sample latitude is invalid")).toBeTruthy();
        expect(screen.getByTestId("admin-locale-7-street-input")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    it("shows the server's message when the list request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<LocalesScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});

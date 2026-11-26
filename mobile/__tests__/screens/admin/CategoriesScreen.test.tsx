import React from "react";
import { Alert } from "react-native";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
const mockApiPost = jest.fn();
const mockApiPatch = jest.fn();
const mockApiDelete = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        delete: (...args: unknown[]) => mockApiDelete(...args),
    },
}));

jest.mock("../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import CategoriesScreen from "../../../src/screens/admin/CategoriesScreen";

const housing = { id: 1, name: "Housing", slug: "housing", active: true, bill_count: 4 };
const parks = { id: 2, name: "Parks", slug: "parks", active: false, bill_count: 1 };

const pressConfirmButton = (spy: jest.SpyInstance, label: string) => {
    const buttons = spy.mock.calls[0][2] as { text: string; onPress?: () => void }[];
    buttons.find((button) => button.text === label)?.onPress?.();
};

// @lat: [[mobile-admin-area#The categories screen]]
describe("CategoriesScreen", () => {
    let alertSpy: jest.SpyInstance;

    beforeEach(() => {
        jest.clearAllMocks();
        alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
        mockApiGet.mockResolvedValue({ categories: [housing, parks] });
    });

    afterEach(() => {
        alertSpy.mockRestore();
    });

    it("lists the category names with their bill counts", async () => {
        render(<CategoriesScreen />);

        expect(await screen.findByText("Housing")).toBeTruthy();
        expect(screen.getByText("Parks")).toBeTruthy();
        expect(screen.getByTestId("admin-category-1-bills")).toHaveTextContent("4 bills");
        expect(screen.getByTestId("admin-category-2-bills")).toHaveTextContent("1 bill");
        expect(mockApiGet).toHaveBeenCalledWith("/admin/categories", expect.anything());
    });

    it("posts the new category name and reloads the list", async () => {
        mockApiPost.mockResolvedValue({ id: 3, name: "Transit", slug: "transit", active: true });
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        fireEvent.changeText(screen.getByTestId("admin-category-new-name-input"), "Transit");
        fireEvent.press(screen.getByTestId("admin-category-add"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/admin/categories", { category: { name: "Transit" } }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        expect(screen.getByTestId("admin-category-new-name-input").props.value).toBe("");
    });

    it("shows the server's message when adding is rejected", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("validation_failed", "Category name is already taken.", undefined, 422),
        );
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        fireEvent.changeText(screen.getByTestId("admin-category-new-name-input"), "Housing");
        fireEvent.press(screen.getByTestId("admin-category-add"));

        expect(await screen.findByText("Category name is already taken.")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    it("renames a category with a PATCH", async () => {
        mockApiPatch.mockResolvedValue({ ...housing, name: "Homes" });
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        fireEvent.press(screen.getByTestId("admin-category-1-rename"));
        expect(screen.getByTestId("admin-category-1-name-input").props.value).toBe("Housing");
        fireEvent.changeText(screen.getByTestId("admin-category-1-name-input"), "Homes");
        fireEvent.press(screen.getByTestId("admin-category-1-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/categories/1", { category: { name: "Homes" } }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        expect(screen.queryByTestId("admin-category-1-name-input")).toBeNull();
    });

    it("activates an inactive category at once", async () => {
        mockApiPatch.mockResolvedValue({ ...parks, active: true });
        render(<CategoriesScreen />);

        await screen.findByText("Parks");
        expect(screen.getByTestId("admin-category-2-active")).toHaveTextContent("Activate");
        fireEvent.press(screen.getByTestId("admin-category-2-active"));

        expect(alertSpy).not.toHaveBeenCalled();
        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/categories/2", { category: { active: true } }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
    });

    it("deactivates only after the admin confirms", async () => {
        mockApiPatch.mockResolvedValue({ ...housing, active: false });
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        expect(screen.getByTestId("admin-category-1-active")).toHaveTextContent("Deactivate");
        fireEvent.press(screen.getByTestId("admin-category-1-active"));

        expect(alertSpy).toHaveBeenCalledWith(
            "Deactivate category?",
            "This removes the category from the taxonomy and the bill filter chips immediately. Existing bill assignments are preserved.",
            expect.any(Array),
        );
        expect(mockApiPatch).not.toHaveBeenCalled();

        pressConfirmButton(alertSpy, "Deactivate");

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/categories/1", { category: { active: false } }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
    });

    it("keeps the category active when the admin declines to deactivate it", async () => {
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        fireEvent.press(screen.getByTestId("admin-category-1-active"));
        const buttons = alertSpy.mock.calls[0][2] as { text: string; style?: string }[];

        expect(buttons.map((button) => button.text)).toEqual(["Keep active", "Deactivate"]);
        expect(buttons[0].style).toBe("cancel");
        expect(mockApiPatch).not.toHaveBeenCalled();
    });

    it("shows Delete only on inactive categories", async () => {
        render(<CategoriesScreen />);

        await screen.findByText("Housing");
        expect(screen.queryByTestId("admin-category-1-delete")).toBeNull();
        expect(screen.getByTestId("admin-category-2-delete")).toBeTruthy();
    });

    it("deletes only after the admin confirms", async () => {
        mockApiDelete.mockResolvedValue(undefined);
        render(<CategoriesScreen />);

        await screen.findByText("Parks");
        fireEvent.press(screen.getByTestId("admin-category-2-delete"));
        expect(mockApiDelete).not.toHaveBeenCalled();

        expect(alertSpy).toHaveBeenCalledWith(
            "Delete category?",
            'This permanently deletes "Parks" and removes it from 1 bill. This cannot be undone.',
            expect.any(Array),
        );

        pressConfirmButton(alertSpy, "Delete");

        await waitFor(() => expect(mockApiDelete).toHaveBeenCalledWith("/admin/categories/2"));
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
    });

    it("shows the server's message when the delete is refused", async () => {
        mockApiDelete.mockRejectedValue(
            new ApiRequestError("validation_failed", "Deactivate the category before deleting it.", undefined, 422),
        );
        render(<CategoriesScreen />);

        await screen.findByText("Parks");
        fireEvent.press(screen.getByTestId("admin-category-2-delete"));
        pressConfirmButton(alertSpy, "Delete");

        expect(await screen.findByText("Deactivate the category before deleting it.")).toBeTruthy();
        expect(screen.getByText("Parks")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    it("shows the server's message when the list request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<CategoriesScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});

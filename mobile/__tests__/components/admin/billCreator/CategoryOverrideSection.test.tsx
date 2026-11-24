import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiDelete = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        delete: (...args: unknown[]) => mockApiDelete(...args),
        get: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import CategoryOverrideSection from "../../../../src/components/admin/billCreator/CategoryOverrideSection";
import SummaryTab from "../../../../src/screens/admin/billCreator/tabs/SummaryTab";

const housing = { id: 1, name: "Housing", active: true };
const zoning = { id: 2, name: "Zoning", active: true };
const finance = { id: 3, name: "Finance", active: true };
const retired = { id: 4, name: "Retired", active: false };

const tabData = (overrides: Record<string, unknown> = {}, billOverrides: Record<string, unknown> = {}) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        bill_llm_provisioning: { id: 9 },
        override_categories: [housing],
        ...billOverrides,
    },
    active_categories: [
        { id: 1, name: "Housing" },
        { id: 2, name: "Zoning" },
        { id: 3, name: "Finance" },
    ],
    max_active_categories_per_bill: 3,
    ...overrides,
});

const renderSection = (data: ReturnType<typeof tabData>, billId: number | null = 42) => {
    const refresh = jest.fn(async () => {});
    const view = render(<CategoryOverrideSection billId={billId} data={data} refresh={refresh} />);
    return { refresh, rerender: view.rerender };
};

// @lat: [[mobile-bill-creator#Sections#The category override section]]
describe("CategoryOverrideSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        mockApiDelete.mockResolvedValue({});
    });

    it("renders under the Summary tab", () => {
        render(<SummaryTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-categories")).toBeTruthy();
    });

    it("lists the assigned categories and offers only the unassigned active ones", () => {
        renderSection(tabData());

        expect(screen.getByTestId("admin-category-1")).toHaveTextContent(/Housing/);
        expect(screen.queryByTestId("admin-category-add-1")).toBeNull();
        expect(screen.getByTestId("admin-category-add-2")).toHaveTextContent("Zoning");
        expect(screen.getByTestId("admin-category-add-3")).toHaveTextContent("Finance");
    });

    it("says no category is assigned when the bill has none", () => {
        renderSection(tabData({}, { override_categories: [] }));

        expect(screen.getByTestId("admin-categories-empty")).toHaveTextContent(
            "No categories assigned yet. Add one below.",
        );
    });

    it("renders nothing for a bill that has not been summarized", () => {
        renderSection(tabData({}, { bill_llm_provisioning: null }));

        expect(screen.queryByTestId("admin-categories")).toBeNull();
    });

    it("renders nothing for a bill that is not saved", () => {
        renderSection(tabData(), null);

        expect(screen.queryByTestId("admin-categories")).toBeNull();
    });

    it("posts the category id and reloads the tab when a category is added", async () => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-category-add-2"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/42/categories", { category_id: 2 }));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("deletes the category and reloads the tab when a category is removed", async () => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-category-1-remove"));

        await waitFor(() => expect(mockApiDelete).toHaveBeenCalledWith("/bills/42/categories/1"));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("labels each remove button with the category name", () => {
        renderSection(tabData());

        expect(screen.getByLabelText("Remove Housing")).toBeTruthy();
    });

    it("shows the server's message and does not reload when an add is refused", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("validation_failed", "Category not found or not available.", undefined, 422),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-category-add-2"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-categories-add-error")).toHaveTextContent(
                "Category not found or not available.",
            ),
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the server's message beside the chip when a removal is refused", async () => {
        mockApiDelete.mockRejectedValue(new ApiRequestError("server_error", "Something went wrong", undefined, 500));
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-category-1-remove"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-category-1-remove-error")).toHaveTextContent("Something went wrong"),
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("stops offering categories once the maximum is assigned", () => {
        renderSection(tabData({}, { override_categories: [housing, zoning, finance] }));

        expect(screen.getByTestId("admin-categories-max")).toHaveTextContent("Maximum 3 categories assigned.");
        expect(screen.queryByTestId("admin-category-add-1")).toBeNull();
    });

    it("counts only active categories against the maximum", () => {
        renderSection(tabData({}, { override_categories: [housing, zoning, retired] }));

        expect(screen.queryByTestId("admin-categories-max")).toBeNull();
        expect(screen.getByTestId("admin-category-add-3")).toBeTruthy();
        expect(screen.getByTestId("admin-category-4")).toHaveTextContent(/Retired/);
    });

    it("keeps offering categories when the server sent no maximum", () => {
        renderSection(
            tabData({ max_active_categories_per_bill: undefined }, { override_categories: [housing, zoning] }),
        );

        expect(screen.queryByTestId("admin-categories-max")).toBeNull();
        expect(screen.getByTestId("admin-category-add-3")).toBeTruthy();
    });

    it("offers a removed category again once the tab reloads without it", () => {
        const { rerender } = renderSection(tabData({}, { override_categories: [housing, zoning, finance] }));
        expect(screen.queryByTestId("admin-category-add-1")).toBeNull();

        rerender(
            <CategoryOverrideSection
                billId={42}
                data={tabData({}, { override_categories: [zoning, finance] })}
                refresh={jest.fn(async () => {})}
            />,
        );

        expect(screen.getByTestId("admin-category-add-1")).toHaveTextContent("Housing");
        expect(screen.queryByTestId("admin-categories-max")).toBeNull();
    });

    it("offers nothing when every active category is assigned", () => {
        renderSection(tabData({ active_categories: [{ id: 1, name: "Housing" }] }));

        expect(screen.queryByTestId("admin-categories-add")).toBeNull();
    });
});

import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockApiPost(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import OrganizationsSection from "../../../../src/components/admin/billCreator/OrganizationsSection";

const savedOrganization = {
    id: 7,
    name: "Harford Road Neighbors",
    icon_url: "https://example.com/harford.png",
    positions: [
        { id: 70, bill_id: 99, support: "AGAINST", summary: "Another bill." },
        { id: 71, bill_id: 42, support: "AGAINST", summary: "Opposes the bill." },
    ],
};

const localeOrganizations = [
    savedOrganization,
    { id: 8, name: "Baltimore Tenants Union", icon_url: null, positions: [] },
];

const data = {
    bill: { id: 42, external_id: "26-0001", title: "A bill", organizations: [savedOrganization] },
    organizations: localeOrganizations,
    tab_key: "creator",
};

const withBillOrganizations = (organizations: unknown[]) => ({
    ...data,
    bill: { ...data.bill, organizations },
});

const renderSection = (overrides: Partial<React.ComponentProps<typeof OrganizationsSection>> = {}) => {
    const refresh = jest.fn().mockResolvedValue(undefined);
    render(<OrganizationsSection billId={42} data={data} refresh={refresh} {...overrides} />);
    return { refresh };
};

const search = (text: string) => fireEvent.changeText(screen.getByTestId("admin-organizations-search"), text);

// @lat: [[mobile-bill-creator#Sections#The organizations section]]
describe("OrganizationsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
    });

    it("posts the bill id with each row's label, support and summary", async () => {
        const { refresh } = renderSection();

        search("tenants");
        fireEvent.press(screen.getByTestId("admin-organizations-option-8"));
        fireEvent.changeText(screen.getByTestId("admin-organizations-row-1-summary"), "Tenants support this bill.");
        search("New Coalition");
        fireEvent.press(screen.getByTestId("admin-organizations-create"));
        fireEvent(screen.getByTestId("admin-organizations-row-2-support"), "valueChange", false);
        fireEvent.changeText(screen.getByTestId("admin-organizations-row-2-summary"), "Opposes it.");

        fireEvent.press(screen.getByTestId("admin-organizations-save"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/organizations?bill_creator_tab=creator", {
            bill_id: 42,
            organizations: [
                {
                    value: 7,
                    label: "Harford Road Neighbors",
                    support: "AGAINST",
                    summary: "Opposes the bill.",
                    icon_url: "https://example.com/harford.png",
                },
                {
                    value: 8,
                    label: "Baltimore Tenants Union",
                    support: "FOR",
                    summary: "Tenants support this bill.",
                    icon_url: null,
                },
                { value: -1, label: "New Coalition", support: "AGAINST", summary: "Opposes it.", icon_url: null },
            ],
        });
        expect(await screen.findByText("Supporting/Opposing Arguments Saved")).toBeTruthy();
        expect(refresh).toHaveBeenCalled();
    });

    it("shows a row error on the row the server named", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Error Saving Supporting/Opposing Arguments",
                {
                    organizations: [
                        { label: null, value: null, summary: null, support: null, icon_url: null },
                        { label: null, value: null, summary: "Summary can't be blank", support: null, icon_url: null },
                    ],
                },
                422,
            ),
        );
        renderSection();
        search("tenants");
        fireEvent.press(screen.getByTestId("admin-organizations-option-8"));

        fireEvent.press(screen.getByTestId("admin-organizations-save"));

        expect(await screen.findByText("Error Saving Supporting/Opposing Arguments")).toBeTruthy();
        expect(screen.getByTestId("admin-organizations-row-1-summary-error").props.children).toBe(
            "Summary can't be blank",
        );
        expect(screen.queryByTestId("admin-organizations-row-0-summary-error")).toBeNull();
    });

    it("starts each saved organization with this bill's position", () => {
        renderSection();

        expect(screen.getByText("Harford Road Neighbors")).toBeTruthy();
        expect(screen.getByTestId("admin-organizations-row-0-summary").props.value).toBe("Opposes the bill.");
        expect(screen.getByTestId("admin-organizations-row-0-support").props.value).toBe(false);
        expect(screen.getByText("Against")).toBeTruthy();
    });

    it("offers only unselected organizations and creates a name no organization has", () => {
        renderSection();

        search("harford road");
        expect(screen.queryByTestId("admin-organizations-option-7")).toBeNull();
        expect(screen.queryByTestId("admin-organizations-create")).toBeTruthy();

        search("  harford   road neighbors ");
        expect(screen.queryByTestId("admin-organizations-create")).toBeNull();

        search("baltimore tenants union");
        expect(screen.getByTestId("admin-organizations-option-8")).toBeTruthy();
        expect(screen.queryByTestId("admin-organizations-create")).toBeNull();
    });

    it("adds the first match, or a new organization, when the search is submitted", () => {
        renderSection();

        search("tenants");
        fireEvent(screen.getByTestId("admin-organizations-search"), "submitEditing");
        expect(screen.getByTestId("admin-organizations-row-1")).toBeTruthy();
        expect(screen.getByText("Baltimore Tenants Union")).toBeTruthy();

        search("Fresh Group");
        fireEvent(screen.getByTestId("admin-organizations-search"), "submitEditing");
        expect(screen.getByText("Fresh Group")).toBeTruthy();
        expect(screen.getByTestId("admin-organizations-search").props.value).toBe("");
    });

    it("labels an Abstain position and keeps it unless the switch is changed", async () => {
        renderSection({
            data: withBillOrganizations([
                { ...savedOrganization, positions: [{ id: 71, bill_id: 42, support: "ABSTAIN", summary: "" }] },
            ]),
        });

        expect(screen.getByText("Abstain")).toBeTruthy();
        fireEvent.press(screen.getByTestId("admin-organizations-save"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost.mock.calls[0][1].organizations[0].support).toBe("ABSTAIN");
    });

    it("shows an empty message before any organization is added", () => {
        renderSection({ data: withBillOrganizations([]) });

        expect(screen.getByText("No organizations selected yet — add one above.")).toBeTruthy();
    });

    it("refuses to save before the bill is saved", () => {
        renderSection({ billId: null });

        fireEvent.press(screen.getByTestId("admin-organizations-save"));

        expect(mockApiPost).not.toHaveBeenCalled();
        expect(screen.getByText("Save the bill before saving organizations.")).toBeTruthy();
    });

    it("sends the Positions tab when the data names no tab", async () => {
        renderSection({ data: { ...data, tab_key: undefined } });

        fireEvent.press(screen.getByTestId("admin-organizations-save"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost.mock.calls[0][0]).toBe("/organizations?bill_creator_tab=positions");
    });
});

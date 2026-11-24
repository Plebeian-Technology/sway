import React from "react";
import { Alert } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiPatch = jest.fn();
const mockApiDelete = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        delete: (...args: unknown[]) => mockApiDelete(...args),
    },
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

const pressConfirmButton = async (spy: jest.SpyInstance, label: string) => {
    const buttons = spy.mock.calls[0][2] as { text: string; onPress?: () => void }[];
    await act(async () => {
        buttons.find((button) => button.text === label)?.onPress?.();
    });
};

const search = (text: string) => fireEvent.changeText(screen.getByTestId("admin-organizations-search"), text);

// @lat: [[mobile-bill-creator#Sections#The organizations section]]
describe("OrganizationsSection", () => {
    let alertSpy: jest.SpyInstance;

    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        mockApiPatch.mockResolvedValue({});
        mockApiDelete.mockResolvedValue(null);
        alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
    });

    afterEach(() => {
        alertSpy.mockRestore();
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

    describe("renaming a row", () => {
        const startRename = (index = 0) =>
            fireEvent.press(screen.getByTestId(`admin-organizations-row-${index}-rename`));

        it("patches the organization's name alone and shows the new name", async () => {
            const { refresh } = renderSection();

            startRename();
            fireEvent.changeText(
                screen.getByTestId("admin-organizations-row-0-rename-input"),
                "  Harford Road Residents ",
            );
            fireEvent.press(screen.getByTestId("admin-organizations-row-0-rename-save"));

            await waitFor(() => expect(mockApiPatch).toHaveBeenCalledTimes(1));
            expect(mockApiPatch).toHaveBeenCalledWith("/organizations/7", { name: "Harford Road Residents" });
            expect(await screen.findByText("Harford Road Residents")).toBeTruthy();
            expect(screen.queryByTestId("admin-organizations-row-0-rename-input")).toBeNull();
            expect(refresh).toHaveBeenCalled();
        });

        it("sends nothing when the name is blank or unchanged, and leaves the editor", () => {
            renderSection();

            startRename();
            fireEvent.changeText(screen.getByTestId("admin-organizations-row-0-rename-input"), "   ");
            fireEvent.press(screen.getByTestId("admin-organizations-row-0-rename-save"));

            expect(mockApiPatch).not.toHaveBeenCalled();
            expect(screen.queryByTestId("admin-organizations-row-0-rename-input")).toBeNull();
            expect(screen.getByText("Harford Road Neighbors")).toBeTruthy();
        });

        it("restores the name when the admin cancels", () => {
            renderSection();

            startRename();
            fireEvent.changeText(screen.getByTestId("admin-organizations-row-0-rename-input"), "Something else");
            fireEvent.press(screen.getByTestId("admin-organizations-row-0-rename-cancel"));
            startRename();

            expect(screen.getByTestId("admin-organizations-row-0-rename-input").props.value).toBe(
                "Harford Road Neighbors",
            );
            expect(mockApiPatch).not.toHaveBeenCalled();
        });

        it("keeps the editor open and shows the server's message when the rename is refused", async () => {
            mockApiPatch.mockRejectedValue(
                new ApiRequestError(
                    "validation_failed",
                    "Could not rename organization: Name has already been taken",
                    undefined,
                    422,
                ),
            );
            const { refresh } = renderSection();

            startRename();
            fireEvent.changeText(
                screen.getByTestId("admin-organizations-row-0-rename-input"),
                "Baltimore Tenants Union",
            );
            fireEvent.press(screen.getByTestId("admin-organizations-row-0-rename-save"));

            expect(await screen.findByText("Could not rename organization: Name has already been taken")).toBeTruthy();
            expect(screen.getByLabelText("Rename Harford Road Neighbors")).toBeTruthy();
            expect(refresh).not.toHaveBeenCalled();
        });

        it("offers no rename for an organization that is not saved yet", () => {
            renderSection();

            search("Fresh Group");
            fireEvent.press(screen.getByTestId("admin-organizations-create"));

            expect(screen.getByTestId("admin-organizations-row-0-rename")).toBeTruthy();
            expect(screen.queryByTestId("admin-organizations-row-1-rename")).toBeNull();
        });
    });

    describe("removing a row", () => {
        it("deactivates the saved position only after the admin confirms, then drops the row", async () => {
            const { refresh } = renderSection();

            fireEvent.press(screen.getByTestId("admin-organizations-row-0-remove"));

            expect(alertSpy).toHaveBeenCalledTimes(1);
            expect(mockApiDelete).not.toHaveBeenCalled();
            expect(screen.getByTestId("admin-organizations-row-0")).toBeTruthy();

            await pressConfirmButton(alertSpy, "Remove");

            await waitFor(() => expect(mockApiDelete).toHaveBeenCalledTimes(1));
            expect(mockApiDelete.mock.calls[0][0]).toBe("/organization_bill_positions/71?bill_creator_tab=creator");
            await waitFor(() => expect(screen.queryByTestId("admin-organizations-row-0")).toBeNull());
            expect(refresh).toHaveBeenCalled();
        });

        it("keeps the row when the admin declines", () => {
            renderSection();

            fireEvent.press(screen.getByTestId("admin-organizations-row-0-remove"));
            const buttons = alertSpy.mock.calls[0][2] as { text: string; style?: string }[];

            expect(buttons.find((button) => button.style === "cancel")).toBeTruthy();
            expect(mockApiDelete).not.toHaveBeenCalled();
            expect(screen.getByTestId("admin-organizations-row-0")).toBeTruthy();
        });

        it("keeps the row and shows the server's message when the removal fails", async () => {
            mockApiDelete.mockRejectedValue(
                new ApiRequestError("not_found", "Organization position not found.", undefined, 404),
            );
            renderSection();

            fireEvent.press(screen.getByTestId("admin-organizations-row-0-remove"));
            await pressConfirmButton(alertSpy, "Remove");

            expect(await screen.findByText("Organization position not found.")).toBeTruthy();
            expect(screen.getByTestId("admin-organizations-row-0")).toBeTruthy();
        });

        it("drops a row that has no saved position without calling the server", async () => {
            renderSection();

            search("tenants");
            fireEvent.press(screen.getByTestId("admin-organizations-option-8"));
            fireEvent.press(screen.getByTestId("admin-organizations-row-1-remove"));
            await pressConfirmButton(alertSpy, "Remove");

            await waitFor(() => expect(screen.queryByTestId("admin-organizations-row-1")).toBeNull());
            expect(mockApiDelete).not.toHaveBeenCalled();
            expect(screen.getByTestId("admin-organizations-row-0")).toBeTruthy();
        });
    });
});

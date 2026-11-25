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

import LegislatorVotesSection from "../../../../src/components/admin/billCreator/LegislatorVotesSection";

const legislators = [
    { id: 4, first_name: "odette", last_name: "ramos", active: true, district: { region_code: "MD", number: 14 } },
    { id: 3, first_name: "zeke", last_name: "cohen", active: true, district: { region_code: "MD", number: 1 } },
    { id: 5, first_name: "ada", last_name: "lovelace", active: false, district: null },
];

const savedVotes = [
    { legislator_id: 3, support: "FOR" },
    { legislator_id: 4, support: "AGAINST" },
];

const choose = (legislatorId: number, support: string) =>
    fireEvent.press(screen.getByTestId(`admin-legislator-votes-${legislatorId}-${support}`));

const isSelected = (legislatorId: number, support: string) =>
    screen.getByTestId(`admin-legislator-votes-${legislatorId}-${support}`).props.accessibilityState.checked;

const renderSection = (overrides: Partial<React.ComponentProps<typeof LegislatorVotesSection>> = {}) =>
    render(
        <LegislatorVotesSection
            billId={42}
            legislators={legislators}
            legislatorVotes={savedVotes}
            refreshedAt={null}
            source={null}
            {...overrides}
        />,
    );

// @lat: [[mobile-bill-creator#Sections#The legislator votes section]]
describe("LegislatorVotesSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
    });

    it("posts the bill id and the changed legislator's support", async () => {
        renderSection();
        choose(4, "ABSTAIN");

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/legislator_votes", {
            bill_id: 42,
            legislator_votes: [
                { legislator_id: 3, support: "FOR" },
                { legislator_id: 4, support: "ABSTAIN" },
            ],
        });
        expect(await screen.findByText("Legislator votes saved.")).toBeTruthy();
    });

    it("lists the legislators by name with their saved vote selected", () => {
        renderSection();

        const rows = screen.getAllByTestId(/^admin-legislator-votes-row-/).map((row) => row.props.testID);
        expect(rows).toEqual([
            "admin-legislator-votes-row-5",
            "admin-legislator-votes-row-4",
            "admin-legislator-votes-row-3",
        ]);
        expect(isSelected(3, "FOR")).toBe(true);
        expect(isSelected(3, "AGAINST")).toBe(false);
        expect(isSelected(4, "AGAINST")).toBe(true);
        expect(isSelected(5, "FOR")).toBe(false);
        expect(screen.getByText("Zeke Cohen")).toBeTruthy();
        expect(screen.getByText("MD · District 14")).toBeTruthy();
    });

    it("stamps a legislator who no longer serves as Former", () => {
        renderSection();

        expect(screen.getAllByText("Former")).toHaveLength(1);
        expect(screen.getByTestId("admin-legislator-votes-former-5")).toBeTruthy();
    });

    it("keeps one position per legislator", () => {
        renderSection();

        choose(3, "ABSTAIN");

        expect(isSelected(3, "ABSTAIN")).toBe(true);
        expect(isSelected(3, "FOR")).toBe(false);
        expect(isSelected(3, "AGAINST")).toBe(false);
    });

    it("keeps a saved vote for a legislator missing from the roster", async () => {
        renderSection({ legislatorVotes: [...savedVotes, { legislator_id: 99, support: "FOR" }] });

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost.mock.calls[0][1].legislator_votes).toEqual([
            { legislator_id: 3, support: "FOR" },
            { legislator_id: 99, support: "FOR" },
            { legislator_id: 4, support: "AGAINST" },
        ]);
    });

    it("says there are no legislators and offers no save when the roster is empty", () => {
        renderSection({ legislators: [] });

        expect(screen.getByText("No legislators available for this locale yet.")).toBeTruthy();
        expect(screen.queryByTestId("admin-legislator-votes-save")).toBeNull();
    });

    it("asks for the bill to be saved first when it has no id", () => {
        renderSection({ billId: null });

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        expect(screen.getByText("Save the bill before saving votes.")).toBeTruthy();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("shows when and where the votes were last refreshed", () => {
        renderSection({ refreshedAt: "2026-11-18 09:30", source: "legistar" });

        expect(screen.getByText("Legislator votes refreshed at 2026-11-18 09:30 from legistar.")).toBeTruthy();
    });

    it("shows no refresh notice unless both the time and the source are known", () => {
        renderSection({ refreshedAt: "2026-11-18 09:30", source: null });

        expect(screen.queryByText(/refreshed at/)).toBeNull();
    });

    it("shows the server's refusal under legislator_votes", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { legislator_votes: "Failed to save votes for legislator(s): 4." },
                422,
            ),
        );
        renderSection();

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        expect(await screen.findByText("Failed to save votes for legislator(s): 4.")).toBeTruthy();
        expect(screen.queryByText("Legislator votes saved.")).toBeNull();
    });

    it("shows the server's message when it names no field", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "No term covers this bill's date for Ada Lovelace. Fix the term and save again.",
                undefined,
                422,
            ),
        );
        renderSection();

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        expect(await screen.findByText(/No term covers this bill's date for Ada Lovelace/)).toBeTruthy();
    });

    it("falls back to the web's refusal text when the server sends none", async () => {
        mockApiPost.mockRejectedValue(new ApiRequestError("validation_failed", "", { legislator_votes: "  " }, 422));
        renderSection();

        fireEvent.press(screen.getByTestId("admin-legislator-votes-save"));

        expect(await screen.findByText("Could not save legislator votes.")).toBeTruthy();
    });
});

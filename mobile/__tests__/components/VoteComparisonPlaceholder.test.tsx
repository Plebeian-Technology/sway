// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
import React from "react";
import * as Clipboard from "expo-clipboard";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { VoteComparisonPlaceholder } from "../../src/components/VoteComparisonPlaceholder";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

let mockCurrentUser: { id?: number; invite_url?: string | null } | null = null;

jest.mock("expo-clipboard", () => ({ setStringAsync: jest.fn() }));

jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => ({ bootstrap: { current_user: mockCurrentUser } }),
}));

const INVITE_URL = "https://app.example.test/invite/7/abc";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("VoteComparisonPlaceholder", () => {
    beforeEach(() => {
        mockCurrentUser = { id: 7, invite_url: INVITE_URL };
        jest.mocked(Clipboard.setStringAsync).mockReset().mockResolvedValue(true);
    });

    test("says how many more users are needed and asks the reader to invite others", () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn />);

        expect(screen.getByText("Visual comparisons will be shown when 3 more users have voted.")).toBeTruthy();
        expect(screen.getByText("Invite others by sharing Sway")).toBeTruthy();
    });

    test("uses the singular when one more user is needed", () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={1} />);

        expect(screen.getByText("Visual comparisons will be shown when 1 more user has voted.")).toBeTruthy();
    });

    test("says only 'Not enough votes yet' when no number is given", () => {
        wrap(<VoteComparisonPlaceholder />);

        expect(screen.getByText("Not enough votes yet")).toBeTruthy();
        expect(screen.queryByText(/Visual comparisons will be shown/)).toBeNull();
        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
    });

    test("copies a signed-in reader's invite link and says it was copied", async () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn />);

        expect(screen.getByText("Copy invite link")).toBeTruthy();
        expect(screen.queryByText("Invite link copied to clipboard.")).toBeNull();

        fireEvent.press(screen.getByTestId("vote-comparison-invite"));

        expect(Clipboard.setStringAsync).toHaveBeenCalledWith(INVITE_URL);
        expect(await screen.findByText("Invite link copied to clipboard.")).toBeTruthy();
    });

    test("says nothing was copied when the clipboard refuses", async () => {
        jest.mocked(Clipboard.setStringAsync).mockResolvedValue(false);
        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn />);

        fireEvent.press(screen.getByTestId("vote-comparison-invite"));

        await screen.findByTestId("vote-comparison-invite");
        expect(Clipboard.setStringAsync).toHaveBeenCalledWith(INVITE_URL);
        expect(screen.queryByText("Invite link copied to clipboard.")).toBeNull();
    });

    test("shows no button for a signed-in reader with no invite link", () => {
        mockCurrentUser = { id: 7, invite_url: null };

        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn />);

        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        expect(screen.queryByTestId("vote-comparison-sign-up")).toBeNull();
    });

    test("shows no button for a signed-in reader whose bootstrap has not loaded", () => {
        mockCurrentUser = null;

        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn />);

        expect(screen.getByText("Invite others by sharing Sway")).toBeTruthy();
        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        expect(screen.queryByTestId("vote-comparison-sign-up")).toBeNull();
    });

    test("offers no invite link to a reader who is not signed in", () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={3} isSignedIn={false} />);

        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        expect(screen.queryByTestId("vote-comparison-sign-up")).toBeNull();
    });
});

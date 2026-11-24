// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
import React from "react";
import { Share } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { VoteComparisonPlaceholder } from "../../src/components/VoteComparisonPlaceholder";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

let mockCurrentUser: { id?: number; invite_url?: string | null } | null = null;

jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => ({ bootstrap: { current_user: mockCurrentUser } }),
}));

const INVITE_URL = "https://app.example.test/invite/7/abc";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("VoteComparisonPlaceholder", () => {
    beforeEach(() => {
        mockCurrentUser = { id: 7, invite_url: INVITE_URL };
        jest.spyOn(Share, "share").mockResolvedValue({ action: "sharedAction" } as never);
    });

    afterEach(() => jest.restoreAllMocks());

    test("says how many more users are needed and asks the reader to invite others", () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={3} />);

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

    test("hands a signed-in reader's invite link to the share sheet", () => {
        wrap(<VoteComparisonPlaceholder votersNeeded={3} />);

        fireEvent.press(screen.getByTestId("vote-comparison-invite"));

        expect(Share.share).toHaveBeenCalledWith({ message: INVITE_URL, url: INVITE_URL });
    });

    test("shows no button for a signed-in reader with no invite link", () => {
        mockCurrentUser = { id: 7, invite_url: null };

        wrap(<VoteComparisonPlaceholder votersNeeded={3} />);

        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        expect(screen.queryByTestId("vote-comparison-sign-up")).toBeNull();
    });

    test("offers a signed-out reader the sign-in prompt", () => {
        mockCurrentUser = null;

        wrap(<VoteComparisonPlaceholder votersNeeded={3} />);

        expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        fireEvent.press(screen.getByTestId("vote-comparison-sign-up"));
        expect(screen.getByTestId("vote-comparison-auth-prompt").props.visible).toBe(true);
    });
});

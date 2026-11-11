import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";

import { VotePanel } from "../../src/components/VotePanel";
import { ApiRequestError } from "../../src/api/errors";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true, loading: false, signOut: jest.fn(), signOutAll: jest.fn() }),
}));

let mockIsOnline = true;
const mockSubmit = jest.fn();
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => ({ submit: mockSubmit, isOnline: mockIsOnline, pending: false }),
}));

jest.mock("../../src/cache/voteCache", () => ({
    get: jest.fn(async () => null),
    set: jest.fn(async () => {}),
}));

const wrap = (props: React.ComponentProps<typeof VotePanel>) =>
    render(
        <ThemeProvider initialMode="light">
            <VotePanel {...props} />
        </ThemeProvider>,
    );

describe("VotePanel disabled-state caption", () => {
    beforeEach(() => {
        mockIsOnline = true;
        mockSubmit.mockReset();
    });

    test("shows no caption while voting is open", () => {
        wrap({ bill: { id: 1, title: "HB 1" }, user_vote: null });
        expect(screen.queryByTestId("vote-panel-caption")).toBeNull();
    });

    test("says why the buttons are dim when the device is offline", () => {
        mockIsOnline = false;
        wrap({ bill: { id: 1, title: "HB 1" }, user_vote: null });
        const caption = screen.getByTestId("vote-panel-caption");
        expect(caption.props.children).toBe(PARITY_COPY.vote.offlineMessage);
        expect(caption.props.className).toContain("text-sm");
        expect(caption.props.className).toContain("text-muted-foreground-light");
    });

    test("says why the buttons are dim when the bill is archived", () => {
        wrap({ bill: { id: 1, title: "HB 1", active: false }, user_vote: null });
        expect(screen.getByTestId("vote-panel-caption").props.children).toBe(PARITY_COPY.votePanel.archivedBill);
    });

    // @lat: [[user-vote-submission#Disabled mobile vote hints]]
    test.each([
        ["a past", "2020-01-01T00:00:00Z"],
        ["a future", "2030-01-01T00:00:00Z"],
    ])("closes voting on an inactive bill with %s release date", (_when, scheduled_release_date_utc) => {
        wrap({
            bill: { id: 1, title: "HB 1", active: false, scheduled_release_date_utc },
            user_vote: null,
        });
        expect(screen.getByTestId("vote-panel-for").props.accessibilityState).toEqual(
            expect.objectContaining({ disabled: true }),
        );
        expect(screen.getByTestId("vote-panel-against").props.accessibilityState).toEqual(
            expect.objectContaining({ disabled: true }),
        );
        expect(screen.getByTestId("vote-panel-caption").props.children).toBe(PARITY_COPY.votePanel.archivedBill);
    });

    test.each([
        ["for", "FOR"],
        ["against", "AGAINST"],
    ] as const)("records a %s vote in words once it is cast", (support, upper) => {
        wrap({ bill: { id: 1, title: "HB 1" }, user_vote: { support } });
        expect(screen.getByTestId("vote-panel-caption").props.children).toBe(PARITY_COPY.votePanel.recordedVote(upper));
    });

    test("prefers the recorded vote over the offline and archived reasons", () => {
        mockIsOnline = false;
        wrap({ bill: { id: 1, title: "HB 1", active: false }, user_vote: { support: "for" } });
        expect(screen.getByTestId("vote-panel-caption").props.children).toBe(PARITY_COPY.votePanel.recordedVote("FOR"));
    });

    test("prefers the archived reason over the offline one", () => {
        mockIsOnline = false;
        wrap({ bill: { id: 1, title: "HB 1", active: false }, user_vote: null });
        expect(screen.getByTestId("vote-panel-caption").props.children).toBe(PARITY_COPY.votePanel.archivedBill);
    });
});

describe("VotePanel submit errors", () => {
    beforeEach(() => {
        mockIsOnline = true;
        mockSubmit.mockReset();
    });

    const castFor = async () => {
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-for"));
        });
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-confirm-submit"));
        });
    };

    test("shows the server's message when it refuses a vote on a bill that is not open", async () => {
        mockSubmit.mockRejectedValue(
            new ApiRequestError("bill_inactive", "Voting is closed for this bill.", undefined, 422),
        );
        wrap({ bill: { id: 1, title: "HB 1" }, user_vote: null });

        await castFor();

        expect(screen.getByTestId("vote-panel-error").props.children).toBe("Voting is closed for this bill.");
    });

    test("keeps the retry text for a failure that a retry can fix", async () => {
        mockSubmit.mockRejectedValue(new ApiRequestError("http_500", "HTTP 500", undefined, 500));
        wrap({ bill: { id: 1, title: "HB 1" }, user_vote: null });

        await castFor();

        expect(screen.getByTestId("vote-panel-error").props.children).toBe("Vote failed. Please try again.");
    });
});

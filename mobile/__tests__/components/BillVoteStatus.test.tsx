import React from "react";
import { render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillVoteStatus } from "../../src/components/BillVoteStatus";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("BillVoteStatus", () => {
    test("says legislators have not yet voted when the bill has no vote date", () => {
        wrap(<BillVoteStatus bill={{}} />);
        expect(screen.getByTestId("bill-header-vote-status").props.children).toBe(
            PARITY_COPY.bill.voteStatus.notYetVoted,
        );
        expect(screen.queryByTestId("bill-header-no-longer-in-office")).toBeNull();
    });

    test("names the chambers that have voted", () => {
        wrap(
            <BillVoteStatus
                bill={{
                    vote_date_time_utc: "2026-03-05T12:00:00Z",
                    house_vote_date_time_utc: "2026-03-03T12:00:00Z",
                    senate_vote_date_time_utc: "2026-03-05T12:00:00Z",
                }}
            />,
        );
        expect(screen.getByText("House voted on March 3, 2026. Senate voted on March 5, 2026.")).toBeTruthy();
    });

    test("adds the no-longer-in-office line for an inactive bill that has a vote date", () => {
        wrap(<BillVoteStatus bill={{ active: false, vote_date_time_utc: "2026-03-03T12:00:00Z" }} />);
        expect(screen.getByTestId("bill-header-no-longer-in-office").props.children).toBe(
            PARITY_COPY.bill.voteStatus.maybeNoLongerInOffice,
        );
    });

    test("omits the no-longer-in-office line for an inactive bill nobody has voted on", () => {
        wrap(<BillVoteStatus bill={{ active: false }} />);
        expect(screen.queryByTestId("bill-header-no-longer-in-office")).toBeNull();
    });

    test("accepts a different test id for the sentence", () => {
        wrap(<BillVoteStatus bill={{}} testID="vote-panel-vote-status" />);
        expect(screen.getByTestId("vote-panel-vote-status")).toBeTruthy();
        expect(screen.queryByTestId("bill-header-vote-status")).toBeNull();
    });
});

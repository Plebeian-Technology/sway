// @lat: [[mobile-bill-surface-components-design#BillHeader]]
import { billVoteStatus } from "../../src/utils/billVoteStatus";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

describe("billVoteStatus", () => {
    test("says legislators have not yet voted when there is no vote date", () => {
        expect(billVoteStatus({})).toBe(PARITY_COPY.bill.voteStatus.notYetVoted);
        expect(billVoteStatus({ vote_date_time_utc: null })).toBe(PARITY_COPY.bill.voteStatus.notYetVoted);
    });

    test("names both chambers and their dates", () => {
        expect(
            billVoteStatus({
                vote_date_time_utc: "2026-03-05T12:00:00Z",
                house_vote_date_time_utc: "2026-03-03T23:30:00Z",
                senate_vote_date_time_utc: "2026-03-05T12:00:00Z",
            }),
        ).toBe("House voted on March 3, 2026. Senate voted on March 5, 2026.");
    });

    test("names only the chamber that has voted", () => {
        expect(
            billVoteStatus({
                vote_date_time_utc: "2026-03-03T12:00:00Z",
                house_vote_date_time_utc: "2026-03-03T12:00:00Z",
            }),
        ).toBe("House voted on March 3, 2026.");
        expect(
            billVoteStatus({
                vote_date_time_utc: "2026-03-04T12:00:00Z",
                senate_vote_date_time_utc: "2026-03-04T12:00:00Z",
            }),
        ).toBe("Senate voted on March 4, 2026.");
    });

    test("falls back to the bare vote date", () => {
        expect(billVoteStatus({ vote_date_time_utc: "2026-03-03T12:00:00Z" })).toBe(
            "Legislators voted on March 3, 2026.",
        );
    });

    test("formats the calendar day in UTC", () => {
        expect(billVoteStatus({ vote_date_time_utc: "2026-03-03T23:59:00Z" })).toBe(
            "Legislators voted on March 3, 2026.",
        );
    });
});

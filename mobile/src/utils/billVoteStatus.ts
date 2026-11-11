// @lat: [[mobile-bill-surface-components-design#BillHeader]]
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface BillVoteDates {
    vote_date_time_utc?: string | null;
    house_vote_date_time_utc?: string | null;
    senate_vote_date_time_utc?: string | null;
}

const formatVoteDate = (iso: string): string =>
    new Date(iso).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" });

export const billVoteStatus = (bill: BillVoteDates): string => {
    const { vote_date_time_utc: vote, house_vote_date_time_utc: house, senate_vote_date_time_utc: senate } = bill;
    if (!vote) return PARITY_COPY.bill.voteStatus.notYetVoted;
    if (house && senate)
        return PARITY_COPY.bill.voteStatus.houseAndSenate(formatVoteDate(house), formatVoteDate(senate));
    if (house) return PARITY_COPY.bill.voteStatus.houseOnly(formatVoteDate(house));
    if (senate) return PARITY_COPY.bill.voteStatus.senateOnly(formatVoteDate(senate));
    return PARITY_COPY.bill.voteStatus.voted(formatVoteDate(vote));
};

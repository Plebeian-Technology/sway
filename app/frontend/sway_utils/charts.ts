import { isEmpty } from "lodash";
import { sway } from "sway";

export const isEmptyScore = (
    score?: sway.scoring.IUserLegislatorScore | sway.IAggregatedBillLocaleScores | sway.IBillScore | null,
) => {
    if (!score || isEmpty(score)) return true;

    if (typeof score === "string") return true;

    if ("districts" in score) {
        return isEmpty(score.districts) || (!score.for && !score.against);
    } else if ("bill_scores" in score) {
        return isEmpty(score.bill_scores) || !score.count_all_users_in_district;
    } else {
        return Object.values(score).every((s) => s === 0);
    }
};

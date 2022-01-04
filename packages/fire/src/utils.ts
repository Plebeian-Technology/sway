/** @format */

import { Support, USER_LEGISLATOR } from "@sway/constants";
import { sway } from "sway";

export const didUserAndLegislatorAgree = (
    userSupport: string,
    legislatorVote: sway.ILegislatorVote | undefined,
): number | null => {
    // Legislator has not voted.
    if (!legislatorVote) return USER_LEGISLATOR.NoLegislatorVote;

    // Legislator abstained from voting.
    if (
        userSupport !== Support.Abstain &&
        legislatorVote.support === Support.Abstain
    ) {
        return USER_LEGISLATOR.NoLegislatorVote;
    }

    if (userSupport === legislatorVote.support) {
        // Both User and Legislator abstained.
        if (userSupport === Support.Abstain)
            return USER_LEGISLATOR.MutuallyAbstained;

        // Both User and Legislator voted For or Against
        return USER_LEGISLATOR.Agreed;
    }
    // User and Legislator voted differently For or Against
    return USER_LEGISLATOR.Disagreed;
};

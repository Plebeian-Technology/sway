/** @format */

import { Collections } from "@sway/constants";
import { sway } from "sway";
import { random } from "lodash";
import { db, firestore } from "../firebase";

export const seedUserLegislatorScores = (
    uid: string,
    locale: sway.ILocale,
    legislator: sway.IBasicLegislator
) => {
    console.log("Seeding user legislator scores for -", legislator.externalId, uid);

    const inc = firestore.FieldValue.increment;
    const unmatched = random(100, 500);
    const abstain = random(100, 500);
    const agreed = random(100, 500);
    const disagree = random(100, 500);

    const district = legislator.district;
    const districtid = district === 0 ? `${legislator.externalId}-${district}` : district.toString();

    db.collection(Collections.UserLegislatorScores)
        .doc(locale.name)
        .collection(legislator.externalId)
        .doc(uid)
        .set({
            externalLegislatorId: legislator.externalId,
            totalUserVotes: inc(
                unmatched / 10 + abstain / 10 + agreed / 10 + disagree / 10
            ),
            totalUnmatchedLegislatorVote: inc(unmatched / 10),
            totalUserLegislatorAbstained: inc(abstain / 10),
            totalUserLegislatorAgreed: inc(agreed / 10),
            totalUserLegislatorDisagreed: inc(disagree / 10),
            userLegislatorVotes: [],
        });
    db.collection(Collections.UserLegislatorScores)
        .doc(locale.name)
        .collection(Collections.Districts)
        .doc(districtid)
        .set({
            externalLegislatorId: legislator.externalId,
            totalUserVotes: inc(unmatched + abstain + agreed + disagree),
            totalUnmatchedLegislatorVote: inc(unmatched),
            totalUserLegislatorAbstained: inc(abstain),
            totalUserLegislatorAgreed: inc(agreed),
            totalUserLegislatorDisagreed: inc(disagree),
            userLegislatorVotes: [],
        });
};

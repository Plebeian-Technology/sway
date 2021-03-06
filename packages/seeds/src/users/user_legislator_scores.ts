/** @format */

import { Collections } from "@sway/constants";
import { sway } from "sway";
import { random } from "lodash";
import { db, firestore } from "../firebase";
import { isAtLargeLegislator } from "../../../webapp/node_modules/@sway/utils/src/legislators";

export const seedUserLegislatorScores = (
    uid: string,
    locale: sway.ILocale,
    legislator: sway.IBasicLegislator,
) => {
    console.log(
        "Seeding user legislator scores for -",
        legislator.externalId,
        uid,
    );

    const inc = firestore.FieldValue.increment;
    const agreed = random(100, 500);
    const disagree = random(100, 500);

    const district = legislator.district;
    const districtid = isAtLargeLegislator(legislator)
        ? `${legislator.externalId}-${district}`
        : district.toString();

    db.collection(Collections.UserLegislatorScores)
        .doc(locale.name)
        .collection(legislator.externalId)
        .doc(uid)
        .set({
            externalLegislatorId: legislator.externalId,
            totalUserVotes: inc(agreed / 10 + disagree / 10),
            totalUserLegislatorAgreed: inc(agreed / 10),
            totalUserLegislatorDisagreed: inc(disagree / 10),
        });
    db.collection(Collections.UserLegislatorScores)
        .doc(locale.name)
        .collection(Collections.Districts)
        .doc(districtid)
        .set({
            externalLegislatorId: legislator.externalId,
            totalUserVotes: inc(agreed + disagree),
            totalUserLegislatorAgreed: inc(agreed),
            totalUserLegislatorDisagreed: inc(disagree),
        });
};

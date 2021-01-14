/** @format */

import { flatten, get } from "lodash";
import { sway } from "sway";
import { firestore } from "../firebase";

const generateLegislatorVote = (
    locale: sway.ILocale,
    legislator: sway.IBasicLegislator,
    bills: sway.IBill[],
) => {
    const [city, region, country] = locale.name.split("-");

    console.log("Generating Legislator Votes");
    const _votes = require(`${__dirname}/../data/${country}/${region}/${city}/legislator_votes`)
        .default;
    const votes = get(_votes, `${country}.${region}.${city}`);

    return bills
        .map((bill: sway.IBill): sway.ILegislatorVote | undefined => {
            if (!votes[bill.firestoreId]) return;
            if (!votes[bill.firestoreId][legislator.externalId]) {
                console.log(
                    "Support on bill cannot be undefined. Skipping legislator vote for -",
                    legislator.externalId,
                    bill.firestoreId,
                );
                return;
            }

            console.log(
                "Generating legislator vote -",
                bill.firestoreId,
                legislator.externalId,
            );
            return {
                createdAt: firestore.FieldValue.serverTimestamp(),
                updatedAt: firestore.FieldValue.serverTimestamp(),
                externalLegislatorId: legislator.externalId,
                billFirestoreId: bill.firestoreId,
                support: votes[bill.firestoreId][legislator.externalId],
            };
        })
        .filter(Boolean) as sway.ILegislatorVote[];
};

export const seedLegislatorVotes = (
    locale: sway.ILocale,
    legislators: sway.IBasicLegislator[],
    bills: sway.IBill[],
) => {
    return flatten(
        legislators.map((legislator: sway.IBasicLegislator) => {
            return generateLegislatorVote(locale, legislator, bills);
        }),
    );
};

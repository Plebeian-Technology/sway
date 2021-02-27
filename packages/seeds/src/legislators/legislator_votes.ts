/** @format */

import { flatten, get } from "lodash";
import { sway } from "sway";

interface ILocaleVotes {
    [billFirestoreId: string]: {
        [externalLegislatorId: string]: "for" | "against" | "abstain";
    };
}

const generateLegislatorVote = (
    legislator: sway.IBasicLegislator,
    bills: sway.IBill[],
    localeVotes: ILocaleVotes,
): sway.ILegislatorVote[] => {
    console.log("Generating Legislator Votes");
    if (legislator.externalId.includes("2016")) return [];

    return bills
        .map((bill: sway.IBill): sway.ILegislatorVote | undefined => {
            if (!localeVotes[bill.firestoreId]) return;
            if (!localeVotes[bill.firestoreId][legislator.externalId]) {
                console.log(
                    "Support undefined for L -",
                    legislator.externalId,
                    " B -",
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
                externalLegislatorId: legislator.externalId,
                billFirestoreId: bill.firestoreId,
                support: localeVotes[bill.firestoreId][legislator.externalId],
            };
        })
        .filter(Boolean) as sway.ILegislatorVote[];
};

export const seedLegislatorVotes = (
    locale: sway.ILocale,
    legislators: sway.IBasicLegislator[],
    bills: sway.IBill[],
) => {
    const [city, region, country] = locale.name.split("-");
    const _votes = require(`${__dirname}/../data/${country}/${region}/${city}/legislator_votes`)
        .default;
    const votes = get(_votes, `${country}.${region}.${city}`);
    return flatten(
        legislators.map((legislator: sway.IBasicLegislator) => {
            return generateLegislatorVote(legislator, bills, votes);
        }),
    );
};

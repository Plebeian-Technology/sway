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
        .map((bill) => {
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

            console.log("Generating legislator vote -", bill.firestoreId, legislator.externalId);
            return {
                externalLegislatorId: legislator.externalId,
                billFirestoreId: bill.firestoreId,
                support: localeVotes[bill.firestoreId][legislator.externalId],
            };
        })
        .filter(Boolean) as sway.ILegislatorVote[];
};

export const seedLegislatorVotes = async (
    locale: sway.ILocale,
    legislators: sway.IBasicLegislator[],
    bills: sway.IBill[],
) => {
    const [city, region, country] = locale.name.split("-");
    const data = await import(
        `${__dirname}/../data/${country}/${region}/${city}/legislator_votes.js`
    );
    if (!data) {
        console.log(
            `No legislator votes data from file - ${__dirname}/../data/${country}/${region}/${city}/legislator_votes.js - skip seeding organizations`,
        );
        return [];
    }

    const votes = get(data, `default.default.${country}.${region}.${city}`);
    return flatten(
        legislators.map((legislator: sway.IBasicLegislator) => {
            return generateLegislatorVote(legislator, bills, votes);
        }),
    );
};

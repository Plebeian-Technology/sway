/** @format */

import { Collections, Support, CONGRESS_LOCALE_NAME, BALTIMORE_CITY_LOCALE_NAME, WASHINGTON_DC_LOCALE_NAME, LOS_ANGELES_LOCALE_NAME } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isCongressLocale } from "@sway/utils";
import { get, isEmpty } from "lodash";
import { sway } from "sway";
import { seedBills } from "../bills";
import { db } from "../firebase";
import { seedUserLegislatorScores } from "../users";
import {
    generateBaltimoreLegislator,
    generateDCLegislator,
    generateLosAngelesLegislator,
    ISeedLegislator,
} from "./factory";
import { seedLegislatorVotes } from "./legislator_votes";
import { seedOrganizations } from "../organizations";
import { default as congressionalVotes } from "../data/united_states/congress/congress/legislator_votes";

interface ICongressVotes {
    [billFirestoreId: string]: {
        [externalLegislatorId: string]: string;
    };
}

const runSeedNonCongressLegislatorVotes = (
    fireClient: SwayFireClient,
    seededLegislatorVotes: sway.ILegislatorVote[],
    legislator: sway.IBasicLegislator,
) => {
    if (fireClient.locale?.name === CONGRESS_LOCALE_NAME) return;

    console.log(
        "Legislator seeded successfully. Seeding legislator votes.",
        legislator.externalId,
    );

    const votes = seededLegislatorVotes.filter(
        (legVote: sway.ILegislatorVote) =>
            legVote.externalLegislatorId === legislator.externalId,
    );

    votes.forEach(async (vote: sway.ILegislatorVote) => {
        createNonExistingLegislatorVote(
            fireClient,
            vote.billFirestoreId,
            vote.externalLegislatorId,
            vote.support,
        );
    });
};

const createNonExistingLegislatorVote = async (
    fireClient: SwayFireClient,
    billFirestoreId: string,
    externalLegislatorId: string,
    support: "for" | "against" | "abstain",
) => {
    const existing = await fireClient
        .legislatorVotes()
        .exists(externalLegislatorId, billFirestoreId);
    if (existing) {
        console.log(`Legislator - ${externalLegislatorId} - vote on bill - ${billFirestoreId} - ALREADY EXISTS. Skipping`);
        return;
    }

    fireClient
        .legislatorVotes()
        .create(externalLegislatorId, billFirestoreId, support);
};

const legislatorGeneratorMethod = (locale: sway.ILocale) => {
    if (locale.name === BALTIMORE_CITY_LOCALE_NAME) {
        return generateBaltimoreLegislator;
    }
    if (locale.name === WASHINGTON_DC_LOCALE_NAME) {
        return generateDCLegislator;
    }
    if (locale.name === LOS_ANGELES_LOCALE_NAME) {
        return generateLosAngelesLegislator;
    }
    if (locale.name === CONGRESS_LOCALE_NAME) {
        throw new Error("Congress locale is not generated.")
    }
    throw new Error(`Locale name not supported - ${locale.name}`)
}

export const seedLegislators = (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    user: sway.IUser,
) => {
    if (!locale) {
        throw new Error(
            `Cannot seed legislators. Locale was falsey. Received - ${user} - ${locale}`,
        );
    }

    console.log("Seeding Legislators for Locale - ", locale.name);
    const [city, region, country] = locale.name.split("-");

    const data = require(`${__dirname}/../data/${country}/${region}/${city}/legislators`)
        .default;

    const localeLegislators: ISeedLegislator[] = get(
        data,
        `${country}.${region}.${city}`,
    );
    const legislators: sway.IBasicLegislator[] = !isCongressLocale(locale)
        ? localeLegislators.map(
              legislatorGeneratorMethod(locale)
          )
        : (localeLegislators as sway.IBasicLegislator[]);

    const bills = seedBills(fireClient, locale);
    seedOrganizations(fireClient, locale);
    const seededLegislatorVotes =
        bills &&
        !isCongressLocale(locale) &&
        seedLegislatorVotes(locale, legislators, bills);

    legislators.forEach(async (legislator: sway.IBasicLegislator) => {
        // const uid = user && user.uid;
        // if (uid && process.env.NODE_ENV !== "production") {
        //     seedUserLegislatorScores(uid, locale, legislator);
        // }

        const current = await fireClient
            .legislators()
            .get(legislator.externalId);
        if (current && current.externalId === legislator.externalId) {
            console.log("Updating Legislator - ", legislator.externalId);
            db.collection(Collections.Legislators)
                .doc(locale.name)
                .collection(Collections.Legislators)
                .doc(legislator.externalId)
                .update({
                    ...current,
                    ...legislator,
                })
                .then(
                    () =>
                        seededLegislatorVotes &&
                        runSeedNonCongressLegislatorVotes(
                            fireClient,
                            seededLegislatorVotes,
                            legislator,
                        ),
                )
                .catch(console.error);
        } else {
            console.log(
                "Seeding/Creating Legislator - ",
                legislator.externalId,
            );
            db.collection(Collections.Legislators)
                .doc(locale.name)
                .collection(Collections.Legislators)
                .doc(legislator.externalId)
                .set(legislator)
                .then(
                    () =>
                        seededLegislatorVotes &&
                        runSeedNonCongressLegislatorVotes(
                            fireClient,
                            seededLegislatorVotes,
                            legislator,
                        ),
                )
                .catch(console.error);
        }
    });

    if (locale.name === CONGRESS_LOCALE_NAME) {
        const votes: ICongressVotes =
            congressionalVotes.united_states.congress.congress;
        Object.keys(votes).forEach((billFirestoreId: string) => {
            console.log("UPDATE CONGRESSIONAL LEGISLATOR VOTES FOR BILL -", billFirestoreId);
            const vote = votes[billFirestoreId];
            const legislatorIds = Object.keys(vote);

            legislatorIds.forEach(async (externalLegislatorId: string) => {
                createNonExistingLegislatorVote(
                    fireClient,
                    billFirestoreId,
                    externalLegislatorId,
                    vote[externalLegislatorId] as "for" | "against" | "abstain",
                );
            });
        });
    }

    return legislators;
};

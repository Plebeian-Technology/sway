/** @format */

import { Collections, Support, CONGRESS_LOCALE_NAME } from "@sway/constants";
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
    if (existing) return;

    fireClient
        .legislatorVotes()
        .create(externalLegislatorId, billFirestoreId, support);
};

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
              locale.name.includes("baltimore")
                  ? generateBaltimoreLegislator
                  : generateDCLegislator,
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
        console.log("UPDATE CONGRESSIONAL LEGISLATOR VOTES");
        const votes: ICongressVotes =
            congressionalVotes.united_states.congress.congress;
        Object.keys(votes).forEach((billFirestoreId: string) => {
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

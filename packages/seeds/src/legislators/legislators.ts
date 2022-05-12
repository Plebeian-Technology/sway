/** @format */

import {
    BALTIMORE_CITY_LOCALE_NAME,
    Collections,
    CONGRESS_LOCALE_NAME,
    LOS_ANGELES_LOCALE_NAME,
    Support,
    WASHINGTON_DC_LOCALE_NAME,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { isCongressLocale, isEmptyObject } from "@sway/utils";
import { get } from "lodash";
import { sway } from "sway";
import { seedBills } from "../bills";
import { default as congressionalVotes } from "../data/united_states/congress/congress/legislator_votes";
import { db, firestore } from "../firebase";
import { seedOrganizations } from "../organizations";
import {
    generateBaltimoreLegislator,
    generateDCLegislator,
    generateLosAngelesLegislator,
    ISeedLegislator,
} from "./factory";
import { seedLegislatorVotes } from "./legislator_votes";

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

    console.log("Legislator seeded successfully. Seeding legislator votes.", legislator.externalId);

    const votes = seededLegislatorVotes.filter(
        (legVote: sway.ILegislatorVote) => legVote.externalLegislatorId === legislator.externalId,
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

export const createNonExistingLegislatorVote = async (
    fireClient: SwayFireClient,
    billFirestoreId: string,
    externalLegislatorId: string,
    support: "for" | "against" | "abstain",
) => {
    if (![Support.For, Support.Against, Support.Abstain].includes(support)) {
        throw new Error(
            `LEGISLATOR - ${externalLegislatorId} - SUPPORT MUST BE ONE OF ${Support.For} | ${Support.Against} | ${Support.Abstain}. RECEIVED - ${support}`,
        );
    }
    // const existing = await fireClient
    //     .legislatorVotes()
    //     .exists(externalLegislatorId, billFirestoreId);
    // if (existing) {
    //     console.log(
    //         `Legislator - ${externalLegislatorId} - vote on bill - ${billFirestoreId} - ALREADY EXISTS. Skipping LegislatorVote create.`,
    //     );
    //     return;
    // }
    // await fireClient
    //     .legislatorVotes()
    //     .create(externalLegislatorId, billFirestoreId, support);
    const existing = await fireClient.legislatorVotes().get(externalLegislatorId, billFirestoreId);
    if (!existing || isEmptyObject(existing)) {
        await fireClient.legislatorVotes().create(externalLegislatorId, billFirestoreId, support);
    } else {
        const existingSupport = existing.support;
        if (
            !existingSupport ||
            ![Support.For, Support.Against, Support.Abstain].includes(existingSupport)
        ) {
            console.log(
                `UPDATING LEGISLATOR - ${externalLegislatorId} - VOTE SUPPORT FROM - ${existingSupport} - TO - ${support} on BILL - ${billFirestoreId}`,
            );
            await fireClient
                .legislatorVotes()
                .updateSupport(externalLegislatorId, billFirestoreId, support);
        }
    }
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
        throw new Error("Congress locale is not generated.");
    }
    throw new Error(`Locale name not supported - ${locale.name}`);
};

export const seedLegislators = async (
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

    const data = await import(`${__dirname}/../data/${country}/${region}/${city}/legislators`);

    const localeLegislators: ISeedLegislator[] = get(data, `${country}.${region}.${city}`);
    const legislators: sway.IBasicLegislator[] = !isCongressLocale(locale)
        ? localeLegislators.map(legislatorGeneratorMethod(locale))
        : (localeLegislators as sway.IBasicLegislator[]);

    const bills = await seedBills(fireClient, locale);
    seedOrganizations(fireClient, locale);
    const seededLegislatorVotes =
        bills &&
        !isCongressLocale(locale) &&
        (await seedLegislatorVotes(locale, legislators, bills));

    legislators.forEach(async (legislator: sway.IBasicLegislator) => {
        const current = await fireClient.legislators().get(legislator.externalId);
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
            console.log("Seeding/Creating Legislator - ", legislator.externalId);
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
        const votes: ICongressVotes = congressionalVotes.united_states.congress.congress;
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

export const seedLegislatorsFromGoogleSheet = (
    locale: sway.ILocale,
    legislators: sway.IBasicLegislator[],
) => {
    const fireClient = new SwayFireClient(db, locale, firestore);

    legislators.forEach(async (legislator: sway.IBasicLegislator) => {
        const current = await fireClient.legislators().get(legislator.externalId);
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
                .catch(console.error);
        } else {
            console.log("Seeding/Creating Legislator - ", legislator.externalId);
            db.collection(Collections.Legislators)
                .doc(locale.name)
                .collection(Collections.Legislators)
                .doc(legislator.externalId)
                .set(legislator)
                .catch(console.error);
        }
    });
};

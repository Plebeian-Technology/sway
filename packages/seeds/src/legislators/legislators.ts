/** @format */

import {
    BALTIMORE_CITY_LOCALE_NAME,
    Collections,
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
import { db, firestoreConstructor } from "../firebase";
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
    if (fireClient.locale?.name.toLowerCase().includes("congress")) return;

    console.log("Legislator seeded successfully. Seeding legislator votes.", legislator.externalId);

    const votes = seededLegislatorVotes.filter(
        (legVote: sway.ILegislatorVote) => legVote.externalLegislatorId === legislator.externalId,
    );

    votes.forEach(async (vote: sway.ILegislatorVote) => {
        await createNonExistingLegislatorVote(
            fireClient,
            vote.billFirestoreId,
            vote.externalLegislatorId,
            vote.support,
        ).catch(console.error);
    });
};

export const createNonExistingLegislatorVote = async (
    fireClient: SwayFireClient,
    billFirestoreId: string,
    externalLegislatorId: string,
    support: "for" | "against" | "abstain",
) => {
    if (![Support.For, Support.Against, Support.Abstain].includes(support)) {
        console.log(
            `LEGISLATOR - ${externalLegislatorId} - SUPPORT MUST BE ONE OF ${Support.For} | ${Support.Against} | ${Support.Abstain}. RECEIVED - ${support}`,
        );
        return;
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
                .updateSupport(externalLegislatorId, billFirestoreId, support)
                .catch(console.error);
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
    if (locale.name.toLowerCase().includes("congress")) {
        throw new Error("Congress locale is not generated.");
    }
    throw new Error(`Locale name not supported - ${locale.name}`);
};

export const seedLegislators = async (
    fireClient: SwayFireClient,
    locale: sway.ILocale,
    user: sway.IUser,
): Promise<sway.IBasicLegislator[]> => {
    if (!locale) {
        throw new Error(
            `Cannot seed legislators. Locale was falsey. Received - ${user} - ${locale}`,
        );
    }

    console.log("Seeding Legislators for Locale - ", locale.name);
    const [city, region, country] = locale.name.split("-");

    console.log(
        "Seeding Legislators from file data -",
        `${__dirname}/../data/${country}/${region}/${city}/legislators/index.js`,
    );
    const data = await import(
        `${__dirname}/../data/${country}/${region}/${city}/legislators/index.js`
    ).catch(console.error);
    if (!data) {
        console.log(
            `No legislator data from file - ${__dirname}/../data/${country}/${region}/${city}/legislators/index.js - skip seeding legislators.`,
        );
        return [];
    } else {
        console.log("Received legislator data for seeds from file.");
        // console.dir(data, { depth: null })
    }

    const localeLegislators: ISeedLegislator[] = get(
        data,
        `default.default.${country}.${region}.${city}`,
    );

    const legislators: sway.IBasicLegislator[] = !isCongressLocale(locale)
        ? localeLegislators.map(legislatorGeneratorMethod(locale))
        : (localeLegislators as sway.IBasicLegislator[]);

    const bills = await seedBills(fireClient, locale).catch(console.error);
    seedOrganizations(fireClient, locale).catch(console.error);
    const seededLegislatorVotes =
        bills &&
        !isCongressLocale(locale) &&
        (await seedLegislatorVotes(locale, legislators, bills).catch(console.error));

    const handleSeedLegislatorVotes = (legislator: sway.IBasicLegislator) => {
        if (seededLegislatorVotes) {
            runSeedNonCongressLegislatorVotes(fireClient, seededLegislatorVotes, legislator);
        }
    };

    if (!Array.isArray(legislators)) {
        console.log("Legislators is NOT an array. Skip seeding legislators.");
        return [];
    }

    const currentLegislators = (await fireClient
        .legislators()
        .where("active", "==", true)
        .get()
        .then((result) => result.docs.map((r) => r.data()))
        .catch((e) => {
            console.error(e);
            return [];
        })) as sway.IBasicLegislator[];

    const inactive = currentLegislators.filter((current) => {
        return !legislators.find((l) => l.externalId === current.externalId);
    });
    inactive.forEach((i) => {
        console.log("seeds.legislators.seedLegislators - deactivate legislator -", i.externalId);
        fireClient
            .legislators()
            .ref(i.externalId)
            .update({ ...i, active: false })
            .catch(console.error);
    });

    legislators.forEach(async (legislator: sway.IBasicLegislator) => {
        const current = currentLegislators.filter((l) => l.externalId === legislator.externalId);

        if (current) {
            console.log(
                "seeds.legislators.seedLegislators - Updating Legislator - ",
                legislator.externalId,
            );
            fireClient
                .legislators()
                .ref(legislator.externalId)
                .update({
                    ...current,
                    ...legislator,
                })
                .then(() => handleSeedLegislatorVotes(legislator))
                .catch(console.error);
        } else {
            console.log(
                "seeds.legislators.seedLegislators - Seeding/Creating Legislator - ",
                legislator.externalId,
            );
            fireClient
                .legislators()
                .ref(legislator.externalId)
                .set(legislator)
                .then(() => handleSeedLegislatorVotes(legislator))
                .catch(console.error);
        }
    });

    if (locale.name.toLowerCase().includes("congress")) {
        // @ts-ignore
        const votes: ICongressVotes = congressionalVotes.united_states.congress.congress;
        Object.keys(votes).forEach((billFirestoreId: string) => {
            console.log("UPDATE CONGRESSIONAL LEGISLATOR VOTES FOR BILL -", billFirestoreId);
            const vote = votes[billFirestoreId];
            const legislatorIds = Object.keys(vote);

            legislatorIds.forEach(async (externalLegislatorId: string) => {
                await createNonExistingLegislatorVote(
                    fireClient,
                    billFirestoreId,
                    externalLegislatorId,
                    vote[externalLegislatorId] as "for" | "against" | "abstain",
                ).catch(console.error);
            });
        });
    }

    return legislators;
};

export const seedLegislatorsFromGoogleSheet = (
    locale: sway.ILocale,
    legislators: sway.IBasicLegislator[],
) => {
    const fireClient = new SwayFireClient(db, locale, firestoreConstructor, console);

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

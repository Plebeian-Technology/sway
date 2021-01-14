/** @format */

import { Collections } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import { get, isEmpty } from "lodash";
import { sway } from "sway";
import { seedBills, seedBillScores } from "../bills";
import { db } from "../firebase";
import { seedUserLegislatorScores } from "../users";
import {
    generateBaltimoreLegislator,
    generateDCLegislator,
    ISeedLegislator,
} from "./factory";
import { seedLegislatorVotes } from "./legislator_votes";
import { seedOrganizations } from "../organizations";

export const seedLegislators = (
    swayFire: SwayFireClient,
    locale: sway.ILocale,
    user: sway.IUser,
) => {
    const uid = user && user.uid;
    if (!locale) {
        throw new Error(
            `Cannot seed legislators. Locale was falsey. Received - ${user.locale}`,
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
    const legislators: sway.IBasicLegislator[] = localeLegislators.map(
        locale.name.includes("baltimore")
            ? generateBaltimoreLegislator
            : generateDCLegislator,
    );

    const bills = seedBills(locale);
    const seededLegislatorVotes = seedLegislatorVotes(
        locale,
        legislators,
        bills,
    );

    seedOrganizations(swayFire, locale);

    legislators.forEach(async (legislator: sway.IBasicLegislator) => {
        console.log("Seeding Legislator - ", legislator.externalId);

        if (uid && process.env.NODE_ENV !== "production") {
            seedUserLegislatorScores(uid, locale, legislator);
        }

        const current = await swayFire.legislators().get(legislator.externalId);
        if (current && current.externalId === legislator.externalId) {
            db.collection(Collections.Legislators)
                .doc(locale.name)
                .collection(Collections.Legislators)
                .doc(legislator.externalId)
                .update({
                    ...current,
                    ...legislator,
                });
        } else {
            db.collection(Collections.Legislators)
                .doc(locale.name)
                .collection(Collections.Legislators)
                .doc(legislator.externalId)
                .set(legislator)
                .then(() => {
                    console.log(
                        "Legislator seeded successfully. Seeding legislator votes.",
                        legislator.externalId,
                    );

                    const votes = seededLegislatorVotes.filter(
                        (legVote: sway.ILegislatorVote) =>
                            legVote.externalLegislatorId ===
                            legislator.externalId,
                    );
                    if (isEmpty(votes)) {
                        console.log(
                            "Legislator votes are empty for legislator. Skipping seed -",
                            legislator.externalId,
                        );
                        return;
                    }
                    const collection = db
                        .collection(Collections.LegislatorVotes)
                        .doc(locale.name)
                        .collection(legislator.externalId);

                    votes.forEach((vote: sway.ILegislatorVote) => {
                        collection
                            .doc(vote.billFirestoreId)
                            .set(vote)
                            .then(() => {
                                console.log("Successfully set legislator vote");
                            })
                            .catch(console.error);
                    });
                })
                .catch(console.error);
        }
    });
    return legislators;
};

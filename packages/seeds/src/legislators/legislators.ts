/** @format */

import { Collections, Support, CONGRESS_LOCALE_NAME } from "@sway/constants";
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
import { updateLegislatorVotes } from "../data/united_states/congress/updateLegislatorVotes";

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
    const legislators: sway.IBasicLegislator[] =
        region !== "congress"
            ? localeLegislators.map(
                  locale.name.includes("baltimore")
                      ? generateBaltimoreLegislator
                      : generateDCLegislator,
              )
            : (localeLegislators as sway.IBasicLegislator[]);

    const bills = seedBills(locale);
    const seededLegislatorVotes =
        bills &&
        region !== "congress" &&
        seedLegislatorVotes(locale, legislators, bills);

    region !== "congress" && seedOrganizations(swayFire, locale);

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

                    if (region === "congress") return;

                    const votes =
                        seededLegislatorVotes &&
                        seededLegislatorVotes.filter(
                            (legVote: sway.ILegislatorVote) =>
                                legVote.externalLegislatorId ===
                                legislator.externalId,
                        );
                    if (!votes || isEmpty(votes)) {
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

    if (locale.name === CONGRESS_LOCALE_NAME) {
        console.log("UPDATE CONGRESSIONAL LEGISLATOR VOTES");
        Promise.all(updateLegislatorVotes())
            .then(() => {
                const congressVotesData = require(`${__dirname}/../data/${country}/${region}/${city}/legislator_votes`)
                    .default;
                const votes = congressVotesData.united_states.congress
                    .congress as {
                    [billid: string]: {
                        [legislatorId: string]: string;
                    };
                };
                Object.keys(votes).forEach((billid: string) => {
                    const vote = votes[billid];
                    const legislatorIds = Object.keys(vote);

                    legislatorIds.forEach((legislatorId: string) => {
                        const legislatorVote: sway.ILegislatorVote = {
                            billFirestoreId: billid,
                            externalLegislatorId: legislatorId,
                            support: vote[legislatorId],
                        };

                        db.collection(Collections.LegislatorVotes)
                            .doc(locale.name)
                            .collection(legislatorId)
                            .doc(billid)
                            .set(legislatorVote)
                            .then(() => {
                                console.log(
                                    "Successfully set legislator vote for bill -",
                                    billid,
                                );
                            })
                            .catch(console.error);
                    });
                });
            })
            .catch(console.error);
    }

    return legislators;
};

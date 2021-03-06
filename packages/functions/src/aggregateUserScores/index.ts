/** @format */

import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { db, firestore } from "../firebase";
import { response } from "../httpTools";
import { fire, sway } from "sway";
import SwayFireClient from "@sway/fire";
import { percentile } from "../percentiles";
import { findLocale } from "@sway/utils";

const { logger } = functions;

interface IReceivedData {
    locale: sway.IUserLocale;
    externalId: string;
    uid: string;
}

/**
 * Aggregate all user_legislator_scores in a district into percentiles
 *
 * @param  {Partial<sway.IUserLocale>} async(data)
 * @param  {CallableContext} context
 */
export const aggregateUserScores = functions.https.onCall(
    async (data: IReceivedData, context: CallableContext) => {
        if (!context.auth?.uid) {
            logger.error("Unauthed request to aggregateUserScores");
            return "invalid credentials";
        }

        const locale = findLocale(data?.locale?.name);
        if (!locale) {
            logger.error(
                `Locale with name - ${data?.locale?.name} - not in LOCALES. Skipping user vote score update.`,
            );
            return;
        }
        const legis = new SwayFireClient(db, locale, firestore);

        const userscoredoc: sway.IUserLegislatorScore | void = await legis
            .userLegislatorScores()
            .get(data.externalId, data.uid);
        if (!userscoredoc) {
            logger.error(
                `could not get user legislator score for uid - ${data.uid}`,
            );
            return response(false, "could not get user legislator score");
        }

        const scoredocs: fire.TypedQuerySnapshot<sway.IUserLegislatorScore> = await legis
            .userLegislatorScores()
            .list(data.externalId);

        const agreedPercents = [];
        const disagreedPercents = [];
        for (let i = 0, len = scoredocs.size; i < len; i++) {
            let {
                externalLegislatorId,
                ...doc
            } = scoredocs.docs[i].data();

            agreedPercents.push(
                doc.totalUserLegislatorAgreed / doc.totalUserVotes,
            );
            disagreedPercents.push(
                doc.totalUserLegislatorDisagreed / doc.totalUserVotes,
            );
        }

        const userAgreedPercent = Math.round(
            (userscoredoc.totalUserLegislatorAgreed /
                userscoredoc.totalUserVotes) *
                100,
        );
        const userDisagreedPercent = Math.round(
            (userscoredoc.totalUserLegislatorDisagreed /
                userscoredoc.totalUserVotes) *
                100,
        );

        const sortedAgreedPercents = agreedPercents
            .sort()
            .map((n: number) => Math.round(n * 100));
        const sortedDisagreedPercents = disagreedPercents
            .sort()
            .map((n: number) => Math.round(n * 100));

        return response(true, "Aggregated scores", {
            userAgreedPercentile: percentile(
                sortedAgreedPercents,
                userAgreedPercent,
            ),
            userDisagreedPercentile: percentile(
                sortedDisagreedPercents,
                userDisagreedPercent,
            ),
            userAgreedPercent,
            userDisagreedPercent,
            sortedAgreedPercents,
            sortedDisagreedPercents,
        });
    },
);

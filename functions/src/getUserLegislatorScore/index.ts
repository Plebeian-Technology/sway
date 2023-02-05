/** @format */

import { Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/v1/https";
import { fire, sway } from "sway";
import { db, firestoreConstructor } from "../firebase";
import { isEmptyObject } from "../utils";

const { logger } = functions;

interface IData extends Partial<sway.IBill> {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}

const DEFAULT_RETURN_VALUE = {
    countAgreed: 0,
    countDisagreed: 0,
    countNoLegislatorVote: 0,
    countLegislatorAbstained: 0,
} as sway.IUserLegislatorScoreV2;

export const getUserLegislatorScore = functions.https.onCall(
    async (data: IData, context: CallableContext): Promise<sway.IUserLegislatorScoreV2> => {
        if (!context.auth?.uid) {
            logger.error("Unauthed request to getUserLegislatorScore");
            return DEFAULT_RETURN_VALUE;
        }
        const { uid } = context.auth;

        const locale = data.locale;
        if (!locale || !locale.name) {
            return DEFAULT_RETURN_VALUE;
        }

        const legislator = data.legislator;
        if (!legislator.externalId || !legislator.district) {
            return DEFAULT_RETURN_VALUE;
        }

        const fireClient = new SwayFireClient(db, locale, firestoreConstructor, logger);
        logger.info(
            `Starting getUserLegislatorScore for locale and legislator - ${locale.name} - ${legislator.externalId}/${legislator.district}`,
        );

        const getLegislatorVotes = async (): Promise<sway.ILegislatorVote[]> => {
            logger.info("getLegislatorVotes for legislator.externalId -", legislator.externalId);
            return fireClient
                .legislatorVotes()
                .getAll(legislator.externalId)
                .catch((e) => {
                    logger.error(e);
                    return [];
                });
        };

        const getUserVotes = async (): Promise<sway.IUserVote[]> => {
            return fireClient
                .userVotes(uid)
                .getAll()
                .catch((e) => {
                    logger.error(e);
                    return [];
                });
        };

        const getActiveBillsIds = async (): Promise<string[]> => {
            return fireClient
                .bills()
                .where("active", "==", true)
                .get()
                .then((snap: fire.TypedQuerySnapshot<sway.IBill>) => {
                    return snap.docs.map((d) => d.data().firestoreId);
                })
                .catch((e) => {
                    logger.error(e);
                    return [];
                });
        };

        const getScores = async (): Promise<sway.IUserLegislatorScoreV2> => {
            const legislatorVotes = await getLegislatorVotes();
            const billIds = await getActiveBillsIds();
            const userVotes = await getUserVotes().then((uvs) =>
                uvs.filter((uv) => billIds.includes(uv.billFirestoreId)),
            );

            if (isEmptyObject(userVotes)) {
                logger.warn("No user votes found for user - ", uid, " skipping get score.");
                return DEFAULT_RETURN_VALUE;
            }

            if (isEmptyObject(legislatorVotes)) {
                logger.warn(
                    "No votes found for legislator - ",
                    legislator.externalId,
                    " skipping get score.",
                );
                return DEFAULT_RETURN_VALUE;
            }

            return userVotes.reduce((sum: sway.IUserLegislatorScoreV2, uv: sway.IUserVote) => {
                const lv = legislatorVotes.find((l) => l.billFirestoreId === uv.billFirestoreId);

                if (!uv.support) {
                    logger.warn(
                        `No user support found on user vote for bill - ${uv.billFirestoreId} in locale - ${locale.name}`,
                    );
                    return sum;
                }

                if (!lv || !lv.support) {
                    sum.countNoLegislatorVote = sum.countNoLegislatorVote + 1;
                    return sum;
                }
                if (lv.support === Support.Abstain) {
                    sum.countLegislatorAbstained = sum.countLegislatorAbstained + 1;
                    return sum;
                }
                if (uv.support === lv.support) {
                    sum.countAgreed = sum.countAgreed + 1;
                    return sum;
                }
                if (uv.support !== lv.support) {
                    sum.countDisagreed = sum.countDisagreed + 1;
                    return sum;
                }

                logger.warn(
                    `Could not calculate agree, disagree, legislator abstained or no legislator vote on bill - ${uv.billFirestoreId} - in locale - ${locale.name}`,
                );
                return sum;
            }, DEFAULT_RETURN_VALUE);
        };

        const finalScores = await getScores();
        logger.info("Returning score data from function", finalScores);
        if (!finalScores) {
            return DEFAULT_RETURN_VALUE;
        } else {
            return finalScores;
        }
    },
);

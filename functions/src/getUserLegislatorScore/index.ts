/** @format */

import { Support } from "@sway/constants";
import SwayFireClient from "@sway/fire";
import * as functions from "firebase-functions";
import { CallableContext } from "firebase-functions/lib/providers/https";
import { fire, sway } from "sway";
import { db, firestore } from "../firebase";
import { isEmptyObject } from "../utils";

const { logger } = functions;

interface IData extends Partial<sway.IBill> {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}

export const getUserLegislatorScore = functions.https.onCall(
    async (
        data: IData,
        context: CallableContext,
    ): Promise<sway.IUserLegislatorScoreV2 | undefined> => {
        if (!context.auth?.uid) {
            logger.error("Unauthed request to getUserLegislatorScore");
            return;
        }
        const { uid } = context.auth;
        const { locale, legislator } = data;

        const fireClient = new SwayFireClient(db, locale, firestore, logger);
        logger.info(
            `Starting getUserLegislatorScore for locale and legislator - ${locale.name} - ${legislator.externalId}/${legislator.district}`,
        );

        const getLegislatorVotes = async (): Promise<sway.ILegislatorVote[] | void> => {
            logger.info("getLegislatorVotes for legislator.externalId -", legislator.externalId);
            return fireClient.legislatorVotes().getAll(legislator.externalId).catch(logger.error);
        };

        const getUserVotes = async (): Promise<sway.IUserVote[] | void> => {
            return fireClient.userVotes(uid).getAll().catch(logger.error);
        };

        const getActiveBillsIds = async (): Promise<string[] | void> => {
            return fireClient
                .bills()
                .where("active", "==", true)
                .get()
                .then((snap: fire.TypedQuerySnapshot<sway.IBill>) => {
                    return snap.docs.map((d) => d.data().firestoreId);
                })
                .catch(logger.error);
        };

        const getScores = () => {
            return Promise.all([getUserVotes(), getLegislatorVotes(), getActiveBillsIds()])
                .then(([_userVotes, legislatorVotes, billIds]) => {
                    if (!_userVotes) {
                        logger.error(
                            "No user votes found for user - ",
                            uid,
                            " skipping get score.",
                        );
                        return;
                    }

                    if (!legislatorVotes || isEmptyObject(legislatorVotes)) {
                        logger.error(
                            "No votes found for legislator - ",
                            legislator.externalId,
                            " skipping get score.",
                        );
                        return;
                    }

                    const userVotes = _userVotes.filter(
                        (uv) => billIds && billIds.includes(uv.billFirestoreId),
                    );

                    if (!userVotes) {
                        logger.error(
                            "Could not get user votes for user - ",
                            uid,
                            " skipping get score.",
                        );
                        return;
                    }
                    if (isEmptyObject(userVotes)) {
                        logger.error(
                            "No user votes found for user - ",
                            uid,
                            " skipping get score.",
                        );
                        return;
                    }

                    return userVotes.reduce(
                        (sum: sway.IUserLegislatorScoreV2, uv: sway.IUserVote) => {
                            const lv = legislatorVotes.find(
                                (l) => l.billFirestoreId === uv.billFirestoreId,
                            );
                            if (!uv.support) {
                                logger.error(
                                    "No user support found on user vote for bill -",
                                    uv.billFirestoreId,
                                    " in locale -",
                                    locale.name,
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

                            logger.error(
                                "Could not calculate agree, disagree, legislator abstained or no legislator vote on bill -",
                                uv.billFirestoreId,
                                " - in locale -",
                                locale.name,
                            );
                            return sum;
                        },
                        {
                            countAgreed: 0,
                            countDisagreed: 0,
                            countNoLegislatorVote: 0,
                            countLegislatorAbstained: 0,
                        },
                    );
                })
                .catch(logger.error);
        };

        const finalScores = await getScores();
        if (!finalScores) {
            logger.error(
                "Error getting user/legislator scores for user -",
                uid,
                "- and legislator -",
                legislator.externalId,
            );
            return {
                countAgreed: 0,
                countDisagreed: 0,
                countNoLegislatorVote: 0,
                countLegislatorAbstained: 0,
            };
        }
        logger.info(
            "Returning score data from function",
            typeof finalScores,
            JSON.stringify(finalScores, null, 4),
        );
        return finalScores;
    },
);
